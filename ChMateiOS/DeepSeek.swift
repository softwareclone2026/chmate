import Foundation
import Security

/// 設定まわりの不具合を切り分けるための簡易ログ。`/tmp/chmate-deepseek.log` に追記する。
enum APIDiagnostics {
    static let path = "/tmp/chmate-deepseek.log"

    static func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - APIキーの保管

/// DeepSeek の API キーを Keychain に保存する。
/// 署名なしのローカル Catalyst ビルドなど、Keychain が使えない環境では
/// UserDefaults に退避し、どちらに保存したかを画面に出す。
enum APIKeyStore {
    /// Keychain のサービス名。アプリの bundle identifier に合わせて導出する。
    /// 固有の文字列を埋め込まないので、fork して bundle identifier を変えても衝突しない。
    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "top.chmate") + ".ai"
    }
    private static let account = "deepseek"
    private static let fallbackKey = "deepseekAPIKeyFallback"
    /// 直近の保存で Keychain がどう応答したか。設定画面の診断表示に使う。
    private(set) static var lastStatus = ""

    @discardableResult
    static func save(_ value: String?) -> String {
        guard let raw = value else { delete(); return "未保存" }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { delete(); return "未保存" }

        // Keychain へ書き、同じセッションで読み戻せるかまで確認する。
        let addStatus = writeKeychain(key)
        let readBack = readKeychain()
        // 署名なしビルドでは次回起動時に読めなくなることがあるため、
        // 読み戻しに成功しても UserDefaults に控えを残して取りこぼしを防ぐ。
        UserDefaults.standard.set(key, forKey: fallbackKey)
        APIDiagnostics.log("save length=\(key.count) add=\(addStatus) readBack=\(readBack == nil ? "nil" : "ok")")
        if addStatus == errSecSuccess, readBack == key {
            lastStatus = "Keychain add=OK read=OK"
            return "Keychain"
        }
        lastStatus = "Keychain add=\(addStatus) read=\(readBack == nil ? "失敗" : "不一致")"
        return "UserDefaults（Keychain利用不可）"
    }

    static func load() -> String? {
        if let key = readKeychain(), !key.isEmpty {
            APIDiagnostics.log("load source=keychain length=\(key.count)")
            return key
        }
        let fallback = UserDefaults.standard.string(forKey: fallbackKey)
        APIDiagnostics.log("load source=\(fallback == nil ? "none" : "userdefaults") length=\(fallback?.count ?? 0)")
        return (fallback?.isEmpty == false) ? fallback : nil
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        APIDiagnostics.log("delete")
        lastStatus = ""
    }

    static var storageDescription: String {
        let keychain = readKeychain() != nil
        let fallback = UserDefaults.standard.string(forKey: fallbackKey) != nil
        if keychain && fallback { return "Keychain（予備: UserDefaults）" }
        if keychain { return "Keychain" }
        if fallback { return "UserDefaults（Keychain利用不可）" }
        return "未保存"
    }

    static var maskedKey: String? {
        guard let key = load(), key.count >= 4 else { return load() == nil ? nil : "••••" }
        return "••••" + key.suffix(4)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func writeKeychain(_ value: String) -> OSStatus {
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func readKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - DeepSeek クライアント

/// DeepSeek の OpenAI 互換 API を呼ぶ。モデルは現行の deepseek-flash を使う。
actor DeepSeekClient {
    static let shared = DeepSeekClient()
    static let modelName = "deepseek-flash"
    static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

    /// リクエスト生成だけを分離しておき、通信なしで検証できるようにする。
    static func makeRequest(prompt: String, review: Bool, apiKey: String, system overrideSystem: String? = nil) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let system = overrideSystem ?? (review
            ? "日本語の校閲者。資料と下書きを比較し、指定されたPASSまたはREWRITE形式を厳守する。資料にない知識は加えない。"
            : "日本語の返信下書きを書く。与えられた発言の意味と数字を正確に扱い、短く自然な日本語で答える。")
        let body: [String: Any] = [
            "model": modelName,
            "messages": [["role": "system", "content": system],
                         ["role": "user", "content": prompt]],
            "stream": false,
            "temperature": review ? 0.15 : 0.35,
            "max_tokens": review ? 900 : 1600
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func generate(_ prompt: String, review: Bool = false, apiKey: String, system: String? = nil) async throws -> String {
        let request = try Self.makeRequest(prompt: prompt, review: review, apiKey: apiKey, system: system)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw NSError(domain: "ChMate.DeepSeek", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "DeepSeekへ接続できませんでした（\(error.localizedDescription)）。"])
        }
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "ChMate.DeepSeek", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "DeepSeekから不正な応答が返りました。"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "ChMate.DeepSeek", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: Self.message(for: http.statusCode, data: data)])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "ChMate.DeepSeek", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "DeepSeekから本文が返されませんでした。"])
        }
        let text = content
            .replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NSError(domain: "ChMate.DeepSeek", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "DeepSeekの応答が空でした。再試行してください。"])
        }
        return text
    }

    static func message(for status: Int, data: Data) -> String {
        switch status {
        case 400: return "DeepSeekのリクエストが不正です。"
        case 401: return "DeepSeekのAPIキーが正しくありません。設定から登録し直してください。"
        case 402: return "DeepSeekの残高が不足しています。"
        case 422: return "DeepSeekのパラメータが不正です。"
        case 429: return "DeepSeekのレート制限に達しました。しばらく待って再試行してください。"
        case 500...599: return "DeepSeek側で障害が発生しています（\(status)）。"
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            return "DeepSeekの呼び出しに失敗しました（\(status)）。\(String(body.prefix(200)))"
        }
    }
}
