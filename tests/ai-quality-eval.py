"""Evaluate real AIService + Ollama calls on a small, attributed fixture set.
No posting. --baseline compares the saved pre-change prompt/review policy using
identical current transport and decoding settings; it is not the old LFM runtime.
"""
from pathlib import Path
import argparse, os, subprocess, tempfile

p = argparse.ArgumentParser()
p.add_argument('--model', required=True)
p.add_argument('--cases',
              default=str(Path(__file__).resolve().parents[1] / 'tests/fixtures/quality-eval-cases.json'),
              help='評価用のレス（既定: tests/fixtures/quality-eval-cases.json）')
p.add_argument('--baseline', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
baseline = root / '.build-smb/quality-eval/AIViews.before.swift'
if a.baseline and not baseline.exists():
    raise SystemExit('--baseline には比較元の AIViews.swift が必要です。'
                     '以前の版を .build-smb/quality-eval/AIViews.before.swift に置いてください。')
policy = baseline if a.baseline else root / 'ChMateiOS/AIViews.swift'
source = policy.read_text().split('struct AIAssistView: View')[0].replace('import SwiftUI', 'import Foundation')
# 移植したネットスラング辞書・プロンプト・パイプラインは Foundation だけで動くので、
# 評価でもアプリと同じ実装をそのまま読み込む。
for extra in ('NetSlangDictionary', 'NetSlangPrompts', 'NetSlangPipeline', 'DeepSeek'):
    source += '\n' + (root / f'ChMateiOS/{extra}.swift').read_text().split('import Foundation', 1)[-1]
backend = (root / 'ChMateiOS/AIBackend.swift').read_text().replace('#if targetEnvironment(macCatalyst)', '#if true')
backend = backend.replace('        return text\n', '        await Trace.shared.record(text, review: review)\n        return text\n')
harness = r'''
struct Post:Codable { let number:Int; let posterID:String; let message:String }
struct LocalLFM { static let shared = LocalLFM(); func generate(_ prompt:String,review:Bool=false,system:String?=nil) async throws -> String { fatalError("not part of this evaluation") } }
struct Fixture:Codable { let id:String; let title:String; let target:String; let context:String; let source:String }
struct TraceEntry:Codable { let review:Bool; let text:String }
actor Trace {
    static let shared = Trace()
    var entries:[TraceEntry] = []
    func record(_ text:String,review:Bool) { entries.append(.init(review:review,text:text)) }
    func reset() { entries=[] }
}
struct Result:Codable { let id:String; let model:String; let response:String; let seconds:Double; let trace:[TraceEntry] }
@main struct Evaluation {
    static func main() async throws {
        let cases = try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let model=CommandLine.arguments[2]
        UserDefaults.standard.set(model,forKey:"aiModelChoice")
        for c in cases {
            await Trace.shared.reset()
            let target=Post(number:3,posterID:"test",message:c.target)
            let context=Post(number:1,posterID:"source",message:c.context)
            let prompt=AIService.prompt(task:.reply,style:.kenmo,title:c.title,target:target,posts:[context,target])
            let start=Date()
            do {
                let text=try await AIService.generate(prompt:prompt,task:.reply)
                let trace=await Trace.shared.entries
                let result=Result(id:c.id,model:model,response:text,seconds:Date().timeIntervalSince(start),trace:trace)
                print(String(data:try JSONEncoder().encode(result),encoding:.utf8)!)
            } catch { print("ERROR \(c.id): \(error)") }
            fflush(stdout)
        }
    }
}
'''
with tempfile.TemporaryDirectory(prefix='chmate-quality-') as directory:
    code = Path(directory) / 'Evaluate.swift'
    binary = Path(directory) / 'Evaluate'
    code.write_text(source + backend + harness)
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    # 同梱辞書を読ませる。無い環境では辞書ブロックが空になるだけで、評価は続く。
    env.setdefault('CHMATE_SLANG_DICT', str(root / 'ChMateiOS/slang.jsonl'))
    subprocess.run(['xcrun','swiftc','-parse-as-library',str(code),'-o',str(binary)],env=env,check=True)
    subprocess.run([str(binary),str(Path(a.cases).resolve()),a.model],env=env,check=True)
