import Foundation

// netslang-chat（日本語ネットスラング読み書きプロジェクト）の
// dictionary.py を Swift へ移植したもの。
// 辞書は JSONL。語を 1 行足すだけで振る舞いが変わり、再学習は要らない。

enum SlangDictionaryError: LocalizedError {
    case brokenJSON(line: Int)
    case missingTerm(line: Int)

    var errorDescription: String? {
        switch self {
        case .brokenJSON(let line): return "辞書の \(line) 行目の JSON を読めません"
        case .missingTerm(let line): return "辞書の \(line) 行目に term がありません"
        }
    }
}

/// 辞書の 1 語。
struct SlangEntry: Hashable {
    let term: String
    var aliases: [String] = []
    var regex: [String] = []
    var reading: String = ""
    var meaning: String = ""
    var usage: [String] = []
    var era: String = ""
    var tags: [String] = []
    var risk: String = "low"
    var note: String = ""

    /// 見出し語と表記ゆれ。重複は落とす。
    var patterns: [String] {
        var seen: [String] = []
        for value in [term] + aliases where !value.isEmpty && !seen.contains(value) {
            seen.append(value)
        }
        return seen
    }

    /// 攻撃的・差別的と受け取られる語。読むための語として扱い、書き込みには使わせない。
    var isRisky: Bool { risk == "medium" || risk == "high" }

    /// 設定画面などに出す 1 行表示。
    var displayLine: String {
        var line = reading.isEmpty ? term : "\(term)（\(reading)）"
        if !meaning.isEmpty { line += ": \(meaning)" }
        var meta: [String] = []
        if !era.isEmpty { meta.append(era) }
        if !tags.isEmpty { meta.append(tags.joined(separator: "/")) }
        if isRisky { meta.append("注意: \(risk)") }
        if !meta.isEmpty { line += "  [" + meta.joined(separator: " / ") + "]" }
        return line
    }
}

/// 入力中で見つかったスラング 1 件。
struct SlangMatch {
    let entry: SlangEntry
    let surface: String
    let position: Int
    let length: Int

    var term: String { entry.term }
    var end: Int { position + length }
}

/// 辞書の読み込み結果。どこから読んだかを画面に出せるように保持する。
struct SlangDictionarySource {
    let entries: [SlangEntry]
    let path: String
    let isExternal: Bool

    var riskyCount: Int { entries.filter { $0.isRisky }.count }
    var description: String { isExternal ? "外部辞書" : "同梱辞書" }
}

/// スラング辞書の読み込みと検索。
enum SlangDictionary {
    static let resourceName = "slang"
    private static let lock = NSLock()
    private static let regexLock = NSLock()
    private static var cached: SlangDictionarySource?
    private static var cachedError: String?
    private static var regexCache: [String: NSRegularExpression] = [:]

    /// 半角英数字だけの語（www など）は URL と誤爆しやすいので境界を見る。
    private static let asciiWord = try? NSRegularExpression(pattern: "^[0-9a-z]+$")

    /// 辞書の探索順。環境変数 → ホーム直下の netslang プロジェクト → 同梱辞書。
    /// netslang-chat を別の場所に置いている場合は、CHMATE_SLANG_DICT に
    /// そのファイルの絶対パスを入れるか、`~/netslang-chat` からリンクする。
    /// `CHMATE_SLANG_NO_EXTERNAL=1` のときは同梱辞書だけを使う（テスト用）。
    static var externalCandidates: [String] {
        var list: [String] = []
        let env = ProcessInfo.processInfo.environment
        if env["CHMATE_SLANG_NO_EXTERNAL"] == "1" {
            return list
        }
        if let custom = env["CHMATE_SLANG_DICT"], !custom.isEmpty {
            list.append(custom)
        }
        let home = NSHomeDirectory()
        list.append("\(home)/netslang-chat/data/slang.jsonl")
        list.append("\(home)/Documents/netslang-chat/data/slang.jsonl")
        return list
    }

    /// 直近の読み込みで起きた問題。設定画面に出す。
    static var loadError: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedError
    }

    static func source() -> SlangDictionarySource {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }

        var text: String?
        var path = ""
        var isExternal = false
        for candidate in externalCandidates {
            if let value = try? String(contentsOfFile: candidate, encoding: .utf8), !value.isEmpty {
                text = value
                path = candidate
                isExternal = true
                break
            }
        }
        if text == nil,
           let url = Bundle.main.url(forResource: resourceName, withExtension: "jsonl"),
           let value = try? String(contentsOf: url, encoding: .utf8) {
            text = value
            path = url.path
            isExternal = false
        }

        guard let text else {
            cachedError = "辞書ファイル（\(resourceName).jsonl）が見つかりません"
            let empty = SlangDictionarySource(entries: [], path: "（未読み込み）", isExternal: false)
            cached = empty
            return empty
        }
        do {
            let entries = try parse(text)
            cachedError = nil
            let loaded = SlangDictionarySource(entries: entries, path: path, isExternal: isExternal)
            cached = loaded
            return loaded
        } catch {
            cachedError = error.localizedDescription
            let empty = SlangDictionarySource(entries: [], path: path, isExternal: isExternal)
            cached = empty
            return empty
        }
    }

    /// 外部で辞書を編集したあとに呼ぶ。
    static func reload() {
        lock.lock()
        cached = nil
        cachedError = nil
        lock.unlock()
        regexLock.lock()
        regexCache = [:]
        regexLock.unlock()
    }

    static func parse(_ text: String) throws -> [SlangEntry] {
        var entries: [SlangEntry] = []
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw SlangDictionaryError.brokenJSON(line: index + 1)
            }
            let term = string(object["term"]).trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { throw SlangDictionaryError.missingTerm(line: index + 1) }
            entries.append(
                SlangEntry(
                    term: term,
                    aliases: strings(object["aliases"]),
                    regex: strings(object["regex"]),
                    reading: string(object["reading"]),
                    meaning: string(object["meaning"]),
                    usage: strings(object["usage"]),
                    era: string(object["era"]),
                    tags: strings(object["tags"]),
                    risk: string(object["risk"]).isEmpty ? "low" : string(object["risk"]),
                    note: string(object["note"])
                )
            )
        }
        return entries
    }

    // MARK: - 検索

    /// 比較用の正規化。表示用の文字列は変換しないこと。
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
    }

    static func matches(in text: String, limit: Int = 8) -> [SlangMatch] {
        matchEntries(in: text, entries: source().entries, limit: limit)
    }

    /// 入力中のスラングを、出現位置の早い順・長い語優先で返す。
    static func matchEntries(in text: String, entries: [SlangEntry], limit: Int = 8) -> [SlangMatch] {
        let haystack = normalize(text)
        var hits: [SlangMatch] = []

        for entry in entries {
            var best: SlangMatch?
            if !entry.regex.isEmpty {
                // 文脈条件付きの語は、正規表現だけを根拠にする。
                for pattern in entry.regex {
                    guard let found = firstRegexMatch(normalize(pattern), in: haystack) else { continue }
                    let candidate = SlangMatch(entry: entry, surface: found.surface, position: found.position, length: found.length)
                    if best == nil || isEarlier(candidate, than: best!) { best = candidate }
                }
            } else {
                for pattern in entry.patterns {
                    let needle = normalize(pattern)
                    guard let position = index(ofNormalized: needle, in: haystack) else { continue }
                    let candidate = SlangMatch(entry: entry, surface: pattern, position: position, length: needle.count)
                    if best == nil || isEarlier(candidate, than: best!) { best = candidate }
                }
            }
            if let best { hits.append(best) }
        }

        hits.sort { ($0.position, -$0.surface.count) < ($1.position, -$1.surface.count) }

        var seen = Set<String>()
        var spans: [(Int, Int)] = []
        var result: [SlangMatch] = []
        for match in hits {
            if seen.contains(match.term) { continue }
            if spans.contains(where: { match.position < $0.1 && $0.0 < match.end }) { continue }
            seen.insert(match.term)
            spans.append((match.position, match.end))
            result.append(match)
            if result.count >= limit { break }
        }
        return result
    }

    /// 辞書引き（設定画面の確認用）。語・読み・意味・別名・タグを対象にする。
    static func search(_ query: String, tag: String? = nil, risk: String? = nil) -> [SlangEntry] {
        let needle = query.isEmpty ? "" : normalize(query)
        return source().entries.filter { entry in
            if let tag, !entry.tags.contains(tag) { return false }
            if let risk, entry.risk != risk { return false }
            guard !needle.isEmpty else { return true }
            let haystack = ([entry.term, entry.reading, entry.meaning] + entry.aliases + entry.tags)
                .map { normalize($0) }
                .joined(separator: " ")
            return haystack.contains(needle)
        }
    }

    /// プロンプトへ差し込む辞書情報。format_entries と同じ書式。
    static func formatEntries(_ matches: [SlangMatch]) -> String {
        guard !matches.isEmpty else {
            return "（辞書に該当なし。辞書に無い語を断定せず、推測と明示すること。）"
        }
        return matches.map { match -> String in
            let entry = match.entry
            var head = "- \(entry.term)"
            if !entry.reading.isEmpty { head += "（\(entry.reading)）" }
            var line = "\(head): \(entry.meaning)"
            var meta: [String] = []
            if !entry.era.isEmpty { meta.append("年代: \(entry.era)") }
            if !entry.tags.isEmpty { meta.append("タグ: " + entry.tags.joined(separator: "/")) }
            if !entry.usage.isEmpty { meta.append("用例: " + entry.usage.joined(separator: " / ")) }
            if entry.isRisky {
                meta.append("注意(\(entry.risk)): " + (entry.note.isEmpty ? "攻撃的・差別的と受け取られる表現" : entry.note))
            } else if !entry.note.isEmpty {
                meta.append("注意: \(entry.note)")
            }
            if !meta.isEmpty { line += " [" + meta.joined(separator: " / ") + "]" }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - 内部

    private static func isEarlier(_ candidate: SlangMatch, than best: SlangMatch) -> Bool {
        (candidate.position, -candidate.length) < (best.position, -best.length)
    }

    private static func index(ofNormalized needle: String, in haystack: String) -> Int? {
        guard !needle.isEmpty else { return nil }
        let ns = needle as NSString
        if let asciiWord, asciiWord.firstMatch(in: needle, range: NSRange(location: 0, length: ns.length)) != nil {
            let pattern = "(?<![0-9a-z./-])\(NSRegularExpression.escapedPattern(for: needle))(?![0-9a-z.])"
            return firstRegexMatch(pattern, in: haystack)?.position
        }
        guard let range = haystack.range(of: needle) else { return nil }
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    private static func firstRegexMatch(_ pattern: String, in haystack: String) -> (position: Int, length: Int, surface: String)? {
        guard let regex = compiled(pattern) else { return nil }
        let ns = haystack as NSString
        guard let match = regex.firstMatch(in: haystack, range: NSRange(location: 0, length: ns.length)),
              match.range.location != NSNotFound,
              let range = Range(match.range, in: haystack) else { return nil }
        let position = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
        let length = haystack.distance(from: range.lowerBound, to: range.upperBound)
        return (position, length, String(haystack[range]))
    }

    private static func compiled(_ pattern: String) -> NSRegularExpression? {
        regexLock.lock(); defer { regexLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache[pattern] = regex
        return regex
    }

    private static func string(_ value: Any?) -> String {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespaces) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func strings(_ value: Any?) -> [String] {
        if let text = value as? String { return text.isEmpty ? [] : [text] }
        if let list = value as? [Any] { return list.map { string($0) }.filter { !$0.isEmpty } }
        return []
    }
}
