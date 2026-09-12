"""ネットスラング辞書を入れたとき／入れないときの生成を実モデルで比べる。

Mac の補助 Ollama（127.0.0.1:11435）と qwen3:4b-instruct-2507-q4_K_M が
必要。生成時間はかかるが、辞書 RAG がレス本文に効いているかを確認する。
"""
from pathlib import Path
import argparse
import json
import os
import subprocess
import tempfile
import urllib.request

root = Path(__file__).resolve().parents[1]
MODEL = "qwen3:4b-instruct-2507-q4_K_M"
HOST = "http://127.0.0.1:11435"
SYSTEM = "日本語の返信下書きを書く。与えられた発言の意味と数字を正確に扱い、短く自然な日本語で答える。"

SAMPLES = [
    ("flow", "fiveCh", "それな〜、ワイもエアプだけど買うわ"),
    ("flow", "nanJ", "情弱乙。型番kwsk"),
]

HARNESS = r'''
struct Post { let number:Int; let posterID:String; let message:String }
enum AIBackend {
    static func generate(_ prompt:String, review:Bool=false, system:String?=nil) async throws -> String { "" }
}
@main struct PromptDump {
    static func main() async {
        let specs: [(AITask, AIStyle, String)] = [
            (.flow, .fiveCh, "それな〜、ワイもエアプだけど買うわ"),
            (.flow, .nanJ, "情弱乙。型番kwsk"),
        ]
        for (task, style, message) in specs {
            let post = Post(number:2, posterID:"", message:message)
            print("<<<PROMPT>>>")
            print(AIService.prompt(task:task, style:style, title:"テストスレ", target:post, posts:[post]))
        }
    }
}
'''


def build_prompts(dictionary: bool) -> list[str]:
    source = (root / "ChMateiOS/AIViews.swift").read_text().split("struct AIAssistView: View")[0].replace("import SwiftUI", "import Foundation")
    for extra in ("NetSlangDictionary.swift", "NetSlangPrompts.swift", "NetSlangPipeline.swift"):
        source += "\n" + (root / "ChMateiOS" / extra).read_text()
    source += HARNESS
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    env["CHMATE_SLANG_DICT"] = str(root / "ChMateiOS/slang.jsonl")
    with tempfile.TemporaryDirectory(prefix="chmate-slang-eval-") as directory:
        swift = Path(directory) / "Dump.swift"
        binary = Path(directory) / "Dump"
        swift.write_text(source)
        subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                        "-module-cache-path", str(Path(directory) / "ModuleCache"),
                        str(swift), "-o", str(binary)], env=env, check=True)
        flip = "" if dictionary else f'UserDefaults.standard.set(false, forKey: NetSlangSettings.storageKey)\n'
        # 辞書を切る場合は起動直後に設定を落とす
        if not dictionary:
            swift.write_text(source.replace("@main struct PromptDump {\n    static func main() async {",
                                             "@main struct PromptDump {\n    static func main() async {\n        " + flip.strip()))
            subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                            "-module-cache-path", str(Path(directory) / "ModuleCache"),
                            str(swift), "-o", str(binary)], env=env, check=True)
        result = subprocess.run([str(binary)], env=env, capture_output=True, text=True, check=True)
    blocks = [b.strip() for b in result.stdout.split("<<<PROMPT>>>") if b.strip()]
    return blocks


def generate(prompt: str, model: str, host: str) -> str:
    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}],
        "stream": False,
        "keep_alive": "5m",
        "options": {"temperature": 0.35, "top_p": 0.9, "repeat_penalty": 1.05, "num_ctx": 4096, "num_predict": 900},
    }).encode()
    request = urllib.request.Request(f"{host}/api/chat", data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=600) as response:
        payload = json.load(response)
    return payload["message"]["content"].strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--limit", type=int, default=len(SAMPLES))
    args = parser.parse_args()

    with_dict = build_prompts(True)[:args.limit]
    without = build_prompts(False)[:args.limit]
    for index, block in enumerate(zip(with_dict, without)):
        task, style, message = SAMPLES[index]
        on, off = block
        print(f"\n=== [{index + 1}] {message} （{style}） ===")
        print(f"辞書ブロック: あり {len(on)} 文字 / なし {len(off)} 文字")
        print("--- 辞書あり ---")
        print(generate(on, args.model, args.host))
        print("--- 辞書なし ---")
        print(generate(off, args.model, args.host))


if __name__ == "__main__":
    main()
