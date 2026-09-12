"""DeepSeek クライアントのリクエスト組み立てを通信なしで検証する。

API キーの扱い、エンドポイント、モデル名、エラー文言を確認する。
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "ChMateiOS/DeepSeek.swift").read_text()

harness = r'''
@main struct DeepSeekCheck {
    static func main() throws {
        let request = try DeepSeekClient.makeRequest(prompt: "テスト本文", review: false, apiKey: "sk-test-123")
        precondition(request.url?.absoluteString == "https://api.deepseek.com/chat/completions",
                     "endpoint mismatch: \(request.url?.absoluteString ?? "nil")")
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123")
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
        precondition(body["model"] as? String == "deepseek-flash")
        precondition(body["stream"] as? Bool == false)
        let messages = body["messages"] as? [[String: String]] ?? []
        precondition(messages.count == 2, "expected system + user message")
        precondition(messages[0]["role"] == "system")
        precondition(messages[1]["role"] == "user")
        precondition(messages[1]["content"] == "テスト本文")
        precondition((body["temperature"] as? Double) == 0.35)

        let review = try DeepSeekClient.makeRequest(prompt: "確認", review: true, apiKey: "k")
        let reviewBody = try JSONSerialization.jsonObject(with: review.httpBody ?? Data()) as? [String: Any] ?? [:]
        precondition((reviewBody["temperature"] as? Double) == 0.15)

        precondition(DeepSeekClient.message(for: 401, data: Data()).contains("APIキー"))
        precondition(DeepSeekClient.message(for: 402, data: Data()).contains("残高"))
        precondition(DeepSeekClient.message(for: 429, data: Data()).contains("レート制限"))
        precondition(DeepSeekClient.message(for: 503, data: Data()).contains("503"))

        print("PASS: DeepSeek endpoint, auth header, model, payload and error messages")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="chmate-deepseek-test-") as directory:
    swift = Path(directory) / "Check.swift"
    binary = Path(directory) / "Check"
    swift.write_text(source + harness)
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    subprocess.run(
        ["xcrun", "swiftc", "-parse-as-library",
         "-module-cache-path", str(Path(directory) / "ModuleCache"),
         str(swift), "-o", str(binary)],
        env=env, check=True)
    subprocess.run([str(binary)], check=True)
