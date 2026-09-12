"""Swift 版スラング辞書が netslang-chat の Python 版と同じ語を拾うか検証する。

matcher（表記ゆれの正規化・正規表現・重なり除去・上限）の挙動を
本家 dictionary.py と突き合わせる。
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
dictionary = root / "ChMateiOS/slang.jsonl"
def _find_project() -> Path:
    """netslang-chat の場所を探す。

    CHMATE_NETSLANG_DIR があればそこを、無ければホーム直下の候補を見る。
    外部ボリュームに置いている場合は環境変数で指定するか、~/netslang-chat から
    リンクしておく。
    """
    candidates = []
    if os.environ.get("CHMATE_NETSLANG_DIR"):
        candidates.append(Path(os.environ["CHMATE_NETSLANG_DIR"]))
    candidates += [
        Path.home() / "netslang-chat",
        Path.home() / "Documents/netslang-chat",
    ]
    for candidate in candidates:
        if (candidate / "netslang/dictionary.py").is_file():
            return candidate
    raise SystemExit("netslang-chat が見つかりません。CHMATE_NETSLANG_DIR に場所を指定してください。")


netslang_project = _find_project()

SAMPLES = [
    "それな〜、この機能マジで草",
    "大草原不可避www",
    "ワロタｗｗｗ",
    "ぴえん🥺",
    "それってあなたの感想ですよね",
    "情弱乙",
    "おつカレー",
    "今日は雨だな",
    "新しいスマホ買った。型番kwsk",
    "ラーメン食ってきた",
    "そこのお前、みたいな",
    "ンゴねぇ",
    "レスありがとナス",
    "スレ立て乙",
    "保守あげとくわ",
    "埋め立てしておく",
    "釣りスレかよ",
    "ソースはよ",
    "ま？それガチ？",
    "〜の民なら分かる",
    "担当者に確認する",
    "野良猫がいる",
    "無職煽りやめろ",
    "メタバースの話",
    "これは仕事で使う普通の文章です。",
    "ふぁっ！？なんだこれ",
    "くさすぎる",
    "草野球の話",
]


def python_matches(project: Path, text: str) -> list[str]:
    sys.path.insert(0, str(project))
    try:
        from netslang.dictionary import load_entries, match_entries  # type: ignore
        return [m.entry.term for m in match_entries(text, load_entries(project / "data/slang.jsonl"))]
    finally:
        sys.path.pop(0)


harness = r'''
@main struct Parity {
    static func main() {
        if CommandLine.arguments.contains("--info") {
            let source = SlangDictionary.source()
            print("count=\(source.entries.count) risky=\(source.riskyCount) external=\(source.isExternal) path=\(source.path)")
            print("error=\(SlangDictionary.loadError ?? "-")")
            return
        }
        var lines: [String] = []
        while let line = readLine(strippingNewline: true) {
            lines.append(line)
        }
        for text in lines {
            let terms = SlangDictionary.matches(in: text).map(\.term)
            // 空行が落ちて行がずれないよう、該当なしは "-" で表す。
            print(terms.isEmpty ? "-" : terms.joined(separator: ","))
        }
    }
}
'''

env = dict(os.environ)
env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
env["CHMATE_SLANG_DICT"] = str(dictionary)

with tempfile.TemporaryDirectory(prefix="chmate-slang-parity-") as directory:
    swift = Path(directory) / "Parity.swift"
    binary = Path(directory) / "Parity"
    sources = [root / "ChMateiOS/NetSlangDictionary.swift",
               root / "ChMateiOS/NetSlangPrompts.swift",
               root / "ChMateiOS/NetSlangPipeline.swift"]
    swift.write_text("\n".join(path.read_text() for path in sources) + harness)
    subprocess.run(
        ["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(Path(directory) / "ModuleCache"),
         str(swift), "-o", str(binary)],
        env=env, check=True)
    result = subprocess.run([str(binary)], input="\n".join(SAMPLES), text=True,
                            capture_output=True, env=env, check=True)
    swift_lines = result.stdout.splitlines()

    # 同梱辞書の経路（iPad 相当）。外部辞書もホームディレクトリも見えない場所で、
    # .app バンドルの Resources/slang.jsonl を読めるかを確認する。
    import shutil
    app = Path(directory) / "Bundle.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources").mkdir(parents=True)
    shutil.copy(binary, app / "Contents/MacOS/Bundle")
    shutil.copy(dictionary, app / "Contents/Resources/slang.jsonl")
    (app / "Contents/Info.plist").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.bundle</string>'
        '<key>CFBundleExecutable</key><string>Bundle</string></dict></plist>\n')
    empty_home = Path(directory) / "empty-home"
    empty_home.mkdir()
    bundle_env = dict(env)
    bundle_env.pop("CHMATE_SLANG_DICT", None)
    bundle_env["CHMATE_SLANG_NO_EXTERNAL"] = "1"
    bundle_env["HOME"] = str(empty_home)
    bundle_env["CFFIXED_USER_HOME"] = str(empty_home)
    info = subprocess.run([str(app / "Contents/MacOS/Bundle"), "--info"], text=True,
                          capture_output=True, env=bundle_env, check=True).stdout
    if "count=278" not in info or "external=false" not in info:
        raise SystemExit(f"同梱辞書を読めていません: {info}")
    print("同梱辞書: " + info.splitlines()[0])

if len(swift_lines) != len(SAMPLES):
    raise SystemExit(f"Swift 側の出力行数が違います: {len(swift_lines)} != {len(SAMPLES)}")

failures = 0
for text, got in zip(SAMPLES, swift_lines):
    expected = python_matches(netslang_project, text)
    actual = [] if got == "-" else got.split(",")
    if expected != actual:
        failures += 1
        print(f"NG  {text!r}\n    python={expected}\n    swift ={got}")

print(f"{len(SAMPLES) - failures}/{len(SAMPLES)} 件一致")
if failures:
    raise SystemExit(1)
print("PASS: Swift 版辞書は netslang-chat の Python 版と同じ語を拾う")
