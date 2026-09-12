import Foundation
import AVFoundation

// MARK: - 書き込みログ（Geschar の KakikomiLogManager 相当）

struct PostedItem: Identifiable, Codable, Hashable {
    var id = UUID()
    let date: Date
    let boardName: String
    let threadTitle: String
    let threadKey: String
    let boardURL: String
    let number: Int?
    let name: String
    let mail: String
    let message: String
}

// MARK: - スレごとの下書き（Geschar の DraftManager 相当）

struct DraftRecord: Codable, Hashable {
    var message: String
    var name: String
    var mail: String
    var updatedAt: Date
    var threadTitle: String
    var boardName: String
}

struct DraftSummary: Identifiable {
    let id: String
    let record: DraftRecord
}

// MARK: - 次スレ候補の探索（Geschar の NextThreadTitleList 相当）

enum ThreadTitle {
    /// 次スレを照合できるようにタイトルを正規化する。
    /// 先頭の【悲報】のような飾り、末尾の ★2 / Part 5 / その3 / (12) を落とす。
    static func normalized(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: "　", with: " ")
        value = value.replacingOccurrences(
            of: #"^\s*[\[【〖(（][^\]】〗)）]{1,14}[\]】〗)）]\s*"#,
            with: "",
            options: .regularExpression
        )
        let suffixes = [
            #"\s*[★☆]\s*[0-9]+\s*$"#,
            #"\s*[Pp][Aa][Rr][Tt]\s*[:：]?\s*[0-9]+\s*$"#,
            #"\s*その\s*[0-9]+\s*$"#,
            #"\s*[（(]\s*[0-9]+\s*[）)]\s*$"#,
            #"\s*[\[【]\s*[0-9]+\s*[\]】]\s*$"#,
            #"\s*[-ー–—]\s*[0-9]+\s*$"#,
            #"\s*第\s*[0-9]+\s*$"#
        ]
        var trimmed = true
        while trimmed {
            trimmed = false
            for pattern in suffixes {
                guard value.range(of: pattern, options: .regularExpression) != nil else { continue }
                value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                trimmed = true
            }
        }
        value = value.replacingOccurrences(of: #"[ 　]+"#, with: "", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum NextThreadFinder {
    /// 同じ板の中で、タイトルが同じで今より新しいスレを候補にする。
    /// 自動移動はせず、候補を提示して選ばせる（Geschar の一覧方式に合わせる）。
    static func candidates(current: ThreadSummary, in threads: [ThreadSummary]) -> [ThreadSummary] {
        let base = ThreadTitle.normalized(current.title)
        guard base.count >= 4 else { return [] }
        let sameTitle = threads.filter { $0.id != current.id && $0.key > current.key && ThreadTitle.normalized($0.title) == base }
        if !sameTitle.isEmpty { return sameTitle }
        // タイトルが少し変わった後継スレを拾う。前方一致のみで誤検出を抑える。
        let prefix = String(base.prefix(10))
        guard prefix.count >= 8 else { return [] }
        return threads.filter { $0.id != current.id && $0.key > current.key && ThreadTitle.normalized($0.title).hasPrefix(prefix) }
    }
}

// MARK: - スレ分析（Geschar の ThreadAnalysisViewController 相当）

struct PosterCount: Identifiable, Hashable {
    var id: String
    var count: Int
}

struct ThreadStatistics {
    var total = 0
    var visible = 0
    var uniqueIDs = 0
    var idless = 0
    var anchors = 0
    var images = 0
    var postsPerHour: Double = 0
    var busiestHour: Int?
    var busiestHourCount = 0
    var topPosters: [PosterCount] = []
    var firstDate: Date?
    var lastDate: Date?
}

enum ThreadAnalyzer {
    static func analyze(posts: [Post], visible: [Post]) -> ThreadStatistics {
        var stats = ThreadStatistics()
        stats.total = posts.count
        stats.visible = visible.count
        var idCounts: [String: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        var dates: [Date] = []
        for post in posts {
            if post.posterID.isEmpty { stats.idless += 1 } else { idCounts[post.posterID, default: 0] += 1 }
            stats.anchors += post.anchors.count
            stats.images += imageURLs(in: post.message).count
            if let date = parse(post.date) {
                dates.append(date)
                hourCounts[Calendar.current.component(.hour, from: date), default: 0] += 1
            }
        }
        stats.uniqueIDs = idCounts.count
        stats.topPosters = idCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(5)
            .map { PosterCount(id: $0.key, count: $0.value) }
        if let busiest = hourCounts.max(by: { $0.value < $1.value }) {
            stats.busiestHour = busiest.key
            stats.busiestHourCount = busiest.value
        }
        stats.firstDate = dates.min()
        stats.lastDate = dates.max()
        if let first = stats.firstDate, let last = stats.lastDate, last > first {
            let span = last.timeIntervalSince(first) / 3600
            if span >= 0.01 { stats.postsPerHour = Double(posts.count) / span }
        }
        return stats
    }

    static func imageURLs(in message: String) -> [URL] {
        message
            .split(whereSeparator: \.isWhitespace)
            .compactMap { URL(string: String($0).trimmingCharacters(in: CharacterSet(charactersIn: "[]()（）"))) }
            .filter { ["png", "jpg", "jpeg", "gif", "webp"].contains($0.pathExtension.lowercased()) }
    }

    /// 「2026/09/09(水) 17:04:21.07 ID:abc」から日時だけ取り出す。
    static func parse(_ text: String) -> Date? {
        guard let match = text.firstMatch(of: #/([0-9]{4})\/([0-9]{2})\/([0-9]{2})[^0-9]{0,6}([0-9]{1,2}):([0-9]{2}):([0-9]{2})/#) else { return nil }
        var components = DateComponents()
        components.year = Int(match.1)
        components.month = Int(match.2)
        components.day = Int(match.3)
        components.hour = Int(match.4)
        components.minute = Int(match.5)
        components.second = Int(match.6)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar.date(from: components)
    }
}

// MARK: - 読み上げ（Geschar の SpeakManager 相当）

final class SpeakManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeakManager()
    static let rateKey = "speechRate"
    static let defaultRate = 0.5

    @Published private(set) var speakingNumber: Int?
    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { speakingNumber != nil }

    static var savedRate: Float {
        let stored = UserDefaults.standard.object(forKey: rateKey) as? Double
        return Float(stored ?? defaultRate)
    }

    func isSpeaking(number: Int) -> Bool { speakingNumber == number }

    func toggle(number: Int, text: String) {
        if speakingNumber == number { stop(); return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        stop()
        let utterance = AVSpeechUtterance(string: body)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = Self.savedRate
        speakingNumber = number
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if speakingNumber != nil { speakingNumber = nil }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakingNumber = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speakingNumber = nil
    }
}
