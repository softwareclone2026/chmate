import Foundation

enum AIModelChoice: String, CaseIterable, Identifiable {
    case deepseek = "deepseek-flash"
    case qwen4 = "qwen3:4b-instruct-2507-q4_K_M"
    case netslang = "chmate-netslang:q4"
    case gemma4 = "gemma3:4b-it-q4_K_M"
    case qwen35 = "qwen3.5:2b"
    case qwen25 = "qwen2.5:3b"
    case local = "local-lfm"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .deepseek: return "DeepSeek（API）"
        case .qwen4: return "Qwen3 4B Instruct（Q4）"
        case .netslang: return "ネッスラ LoRA（5ch文体・Q4）"
        case .gemma4: return "Gemma 3 4B（Q4）"
        case .qwen35: return "Qwen 3.5 2B（Ollama）"
        case .qwen25: return "Qwen 2.5 3B（Ollama）"
        case .local: return "LFM 1.2B（軽量・同梱）"
        }
    }
    /// Mac の Ollama が必要なモデルかどうか。
    var needsOllama: Bool {
        switch self {
        case .deepseek, .local: return false
        default: return true
        }
    }
    /// そのプラットフォームで選べるモデル。
    static var available: [AIModelChoice] {
#if targetEnvironment(macCatalyst)
        return [.deepseek, .qwen4, .netslang, .gemma4, .qwen35, .qwen25, .local]
#else
        // iPad ではクラウドの DeepSeek か、同梱の LFM だけが動く。
        return [.deepseek, .local]
#endif
    }
    static var platformDefault: AIModelChoice {
#if targetEnvironment(macCatalyst)
        return .qwen4
#else
        return APIKeyStore.load() == nil ? .local : .deepseek
#endif
    }
    static var selected: Self {
        let stored = UserDefaults.standard.string(forKey: "aiModelChoice") ?? ""
        guard let choice = AIModelChoice(rawValue: stored), available.contains(choice) else {
            return platformDefault
        }
        return choice
    }
    /// 設定画面で API キーを保存したときに既定へ切り替える。
    static func makeDefault(_ choice: AIModelChoice) {
        UserDefaults.standard.set(choice.rawValue, forKey: "aiModelChoice")
    }
}

enum AIBackend {
    /// system を渡すと、用途別のシステムプロンプトで上書きする（スラング解説など）。
    static func generate(_ prompt: String, review: Bool = false, system: String? = nil) async throws -> String {
        try Task.checkCancellation()
        let choice = AIModelChoice.selected
        switch choice {
        case .deepseek:
            guard let key = APIKeyStore.load(), !key.isEmpty else {
                throw NSError(domain: "ChMate.DeepSeek", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "DeepSeekのAPIキーが未設定です。設定 → DeepSeek で登録してください。"])
            }
            return try await DeepSeekClient.shared.generate(prompt, review: review, apiKey: key, system: system)
        case .local:
            return try await LocalLFM.shared.generate(prompt, review: review, system: system)
        default:
#if targetEnvironment(macCatalyst)
            // Ollama は Mac 上の補助プロセス。失敗しても別モデルへ黙って切り替えない。
            return try await OllamaQwen.shared.generate(prompt, review: review, model: choice.rawValue, system: system)
#else
            throw NSError(domain: "ChMate.AI", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "\(choice.label)はMac版でのみ利用できます。DeepSeekかLFMを選んでください。"])
#endif
        }
    }

    /// 設定画面の接続テスト。短いプロンプトだけを送る。
    static func testDeepSeek(apiKey: String) async throws -> String {
        try await DeepSeekClient.shared.generate("日本語で「接続OK」とだけ返してください。", review: false, apiKey: apiKey)
    }
}

// Ollama は Mac 上の補助プロセスなので、Mac Catalyst ビルドだけに含める。
// iPad 実機ビルドではこの型ごと除外され、通信経路も残らない。
#if targetEnvironment(macCatalyst)
actor OllamaQwen {
    static let shared = OllamaQwen()

    func generate(_ prompt: String, review: Bool = false, model: String, system overrideSystem: String? = nil) async throws -> String {
        let sharedModel = model == AIModelChoice.qwen4.rawValue
            || model == AIModelChoice.gemma4.rawValue
            || model == AIModelChoice.netslang.rawValue
        let baseURL = URL(string: sharedModel ? "http://127.0.0.1:11435" : "http://127.0.0.1:11434")!
        var request = URLRequest(url: baseURL.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // ネッスラ LoRA は文体の主張が強く、高い温度だと語尾が重なりやすい
        // （「〜の？だろ」）。このモデルだけ少し低い温度で安定させる。
        let draftTemperature = model == AIModelChoice.netslang.rawValue ? 0.22 : 0.35
        let system = overrideSystem ?? (review
            ? "日本語の校閲者。資料と下書きを比較し、指定されたPASSまたはREWRITE形式を厳守する。資料にない知識は加えない。"
            : "日本語の返信下書きを書く。与えられた発言の意味と数字を正確に扱い、短く自然な日本語で答える。")
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
            "stream": false,
            "keep_alive": "5m",
            "options": ["temperature": review ? 0.15 : draftTemperature, "top_p": 0.9,
                        "presence_penalty": 0.0, "repeat_penalty": 1.05,
                        "num_ctx": 4096, "num_predict": 900]
        ]
        if model.hasPrefix("qwen3.5") { body["think"] = false }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .networkConnectionLost || error.code == .timedOut {
            throw NSError(domain: "ChMate.Ollama", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ollamaに接続できないか、応答が時間切れになりました。scripts/run-local.commandから起動し直してください。"])
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "ChMate.Ollama", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ollamaで\(model)を利用できません。モデルがインストールされているか確認してください。"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["done_reason"] as? String != "length" else {
            throw NSError(domain: "ChMate.Ollama", code: 4, userInfo: [NSLocalizedDescriptionKey: "生成が長くなり途中で終了しました。短い処理を選んで再試行してください。"])
        }
        let message = json?["message"] as? [String: Any]
        let text = (message?["content"] as? String ?? "")
            .replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NSError(domain: "ChMate.Ollama", code: 3, userInfo: [NSLocalizedDescriptionKey: "モデルから本文が返されませんでした"])
        }
        return text
    }
}
#endif
