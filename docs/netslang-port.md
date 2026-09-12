# ネットスラング読み書きプロジェクトの移植

`netslang-chat`（日本語ネットスラングの読み書きに特化した
Python プロジェクト）の実装を、ChMate の AI 機能へ移植したものです。
ChMate 側の生成モデル（Ollama / DeepSeek / 同梱LFM）はそのままで、
**プロンプトの組み立てだけ**を netslang 流に置き換えています。

## 考え方

```
入力 → 辞書検索（表記ゆれを正規化して一致）→ 該当語をプロンプトに注入 → 生成
```

スラングは寿命が短く、意味の更新も速い。そこで意味は辞書と検索で担保し、
文体はプロンプトに任せます。辞書に 1 行足せば、その語の扱いがすぐ変わります。

## 移植したファイル

| ChMate 側 | 元（netslang-chat） | 内容 |
| --- | --- | --- |
| `ChMateiOS/NetSlangDictionary.swift` | `netslang/dictionary.py` | JSONL 辞書の読み込み、NFKC 正規化、別名・正規表現つきの一致、重なり除去、上位 8 語 |
| `ChMateiOS/NetSlangPrompts.swift` | `netslang/prompts.py` | 読み（解読）・書き（レス）のシステムプロンプト、文体ルール（5ch / なんJ / X）、文体見本 |
| `ChMateiOS/NetSlangPipeline.swift` | `netslang/pipeline.py` | 辞書 RAG の組み立て、読みモードのプロンプト、文体ヒント |
| `ChMateiOS/slang.jsonl` | `data/slang.jsonl` | 辞書本体（278 語。うち読み専用 42 語） |

## ChMate 側の使い方

- AI アシスト画面の「ネットスラング辞書」で、対象のレスから拾った語を確認できます。
- 処理に「スラング解説」を選ぶと、netslang の読み（解読）モードで
  「意味（標準語訳）／語句の解説／注意点」を返します。投稿用の下書きは作りません。
- 返信案などの書きモードでは、口調に応じて 5ch / なんJ の文体ルールと見本、
  辞書の該当語がプロンプトに差し込まれます。
- 設定 →「ネットスラング辞書」で有効・無効の切り替え、収録数、読み込み元、
  辞書引き（検索）、再読み込みができます。

`risk` が medium / high の語は「読むための語」です。意味の説明には使いますが、
書き込みには使わないようプロンプトで指示します。

## 辞書の更新

辞書は JSONL（1 行 1 語）です。次の順に探し、最初に見つかったものを使います。

1. 環境変数 `CHMATE_SLANG_DICT` のパス
2. `~/netslang-chat/data/slang.jsonl`
3. `~/Documents/netslang-chat/data/slang.jsonl`
4. アプリ同梱の `slang.jsonl`（既定。iPad ではこれ）

Mac で netslang 側の辞書を育てている場合は、`scripts/run-local.command` が
配置先アプリの同梱辞書を書き換えてから起動するため、語を足して起動し直せば
反映されます（設定の「辞書を再読み込み」でも再取得できます）。その場の
ファイルを直接読ませたいときは `CHMATE_SLANG_DICT` に絶対パスを入れます。
iPad は同梱辞書を使うため、更新するには `ChMateiOS/slang.jsonl` を差し替えて
ビルドし直します。

## 移植していないもの

- URL 取り込み（`ingest.py`）: 外部ページの取得と語彙抽出。Mac 側の netslang で
  実行して辞書を育てる運用にしています。
- LoRA の追加学習（`lora.py` / `scripts/train_lora.sh`）: 学習は Python 側の仕事。
  学習済みアダプタは `scripts/export_lora_gguf.py` で GGUF へ変換してから
  Ollama の `ADAPTER` で適用します。手順と評価は
  [ai-models.md](ai-models.md) の「ネッスラ LoRA」を参照してください。
- 会話モードと Web UI: ChMate は掲示板クライアントなので不要です
  （プロンプトだけ `NetSlangPrompts.chatSystem` に残しています）。

## 検証

```sh
# 辞書の一致が本家 Python 版と同じか（28 例）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 tests/netslang-dictionary-parity.py

# プロンプト組み立て・校閲・辞書 RAG の回帰
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 tests/ai-generation-regression.py
```

`tests/netslang-dictionary-parity.py` は Swift 版と Python 版へ同じ文を投げ、
拾った語が一致するかを照合します。表記ゆれ（`ｗ`→`w`）、正規表現つきの語、
1 文字語、重なった一致の処理まで含めて比較します。
