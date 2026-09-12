import Foundation
import LeapSDK

actor LocalLFM {
    static let shared = LocalLFM()
    static let resourceName = "LFM2.5-1.2B-JP-8da4w_output_8da8w-seq_4096"
    private var runner: (any ModelRunner)?

    func generate(_ prompt: String, review: Bool = false, system overrideSystem: String? = nil) async throws -> String {
        guard let modelURL = Bundle.main.url(forResource: Self.resourceName, withExtension: "bundle") else {
            throw NSError(domain: "ChMate.LFM", code: 1, userInfo: [NSLocalizedDescriptionKey: "同梱LFM2.5-1.2B-JPモデルが見つかりません"])
        }
        let modelRunner: any ModelRunner
        if let runner {
            modelRunner = runner
        } else {
            let loaded = try Leap.load(options: .init(bundlePath: modelURL.path()))
            runner = loaded
            modelRunner = loaded
        }
        let system = overrideSystem ?? (review ? "日本語の校閲者です。資料を根拠にPASSまたはREWRITE形式で答えてください。" : "日本語の返信下書きを作成します。元の数字と意味を変えず、短い自然な本文だけを書いてください。")
        let conversation = modelRunner.createConversation(systemPrompt: system)
        let message = ChatMessage(role: .user, content: [.text(prompt)])
        var result = ""
        let options = GenerationOptions(temperature: review ? 0.15 : 0.4, topP: 0.9, repetitionPenalty: 1.05, rngSeed: UInt64.random(in: 1...UInt64.max), resetHistory: true, sequenceLength: 4096, maxOutputTokens: 900, enableThinking: false)
        for try await event in conversation.generateResponse(message: message, generationOptions: options) {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text): result += text
            case .reasoningChunk: break
            case .complete: break
            default: break
            }
        }
        let trimmed = result
            .replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(回答|返信|投稿本文)\s*[:：]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NSError(domain: "ChMate.LFM", code: 2, userInfo: [NSLocalizedDescriptionKey: "LFMから本文が返されませんでした"] ) }
        return trimmed
    }
}
