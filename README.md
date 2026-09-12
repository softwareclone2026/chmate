# ChMate

5ちゃんねる（5ch）のクライアントです。同じ読み書きの操作を、Swift 版
（macOS / iPad）と Electron 版（Windows / macOS）の 2 つの実装で提供します。
AI によるレス生成・要約・分析は、ローカルの Ollama、DeepSeek のクラウド API、
またはアプリに同梱する小型モデルで動かせます。

| 実装 | 対応プラットフォーム | ソース | ビルド |
| --- | --- | --- | --- |
| Swift 版 | macOS（Mac Catalyst）、iPad | `ChMateiOS/` | Xcode |
| Electron 版 | Windows、macOS | `recovered-app/` | Node.js |

## 主な機能

読み書きは、板一覧、スレ一覧、レス表示、書き込み、下書きの自動保存、書き込み
ログ、しおりと自動スクロール、レスごとの読み上げ、画像と動画の表示、NG と
長押し NG で構成しています。

AI は返信の下書き、スレ要約、スレ分析、生成後の校閲、スラング解説を用意して
います。返信先とスレ冒頭だけを短く渡し、資料にない統計や体験談を足さないよう
プロンプトで指示します。数字や主語を変えないことも明示しています。詳細は
[docs/ai-models.md](docs/ai-models.md) にまとめています。

ネットスラングは JSONL の辞書で表記ゆれを正規化し、該当語をプロンプトへ注入
します。意味は辞書、文体はプロンプトが担う分担です。移植の内容は
[docs/netslang-port.md](docs/netslang-port.md)、他アプリから取り込んだ機能は
[docs/geschar-features.md](docs/geschar-features.md) にあります。

## 必要なもの

- Swift 版: macOS 26.5 以降と Xcode 26.6 以降。iPad 版は iPadOS 26.5 以降
- Electron 版: Node.js 20 以降と Electron
- Ollama を使う場合: Ollama 本体と生成モデル（後述）

Swift 版の依存は Swift Package Manager が取得します。`LeapSDK`
（`https://github.com/Liquid4All/leap-ios.git`、0.9.4）と `swift-syntax`
（600.0.1）を `ChMateiOS.xcodeproj` が参照しています。

## ビルド（macOS / iPad）

Mac Catalyst 版は次のコマンドでビルドします。インデックス生成は外部ボリューム
と相性が悪いため無効にしています。

```sh
cd chMate-windows
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ChMateiOS.xcodeproj -scheme ChMateiOS \
  -configuration Debug \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$PWD/.build-smb/DerivedData" \
  -clonedSourcePackagesDirPath "$PWD/.build-smb/SourcePackages" \
  -skipMacroValidation -jobs 2 CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO build
```

成果物は
`.build-smb/DerivedData/Build/Products/Debug-maccatalyst/ChMate.app`
です。Xcode で開く場合は `ChMateiOS.xcodeproj` をそのまま使えます。

iPad 版は同じプロジェクトです。`-destination 'generic/platform=iOS'` を指定し、
署名を有効にしてビルドします。実機へ入れるときは Xcode から実行するのが簡単
です。iPad では Ollama が動かないため、選べる生成モデルは DeepSeek と同梱の
LFM だけになります。

`ChMateiOS/` は Xcode の同期グループなので、ファイルを足しても
`project.pbxproj` を編集する必要はありません。

### 同梱モデル（LFM 1.2B）について

`ChMateiOS/LFM2.5-1.2B-JP-8da4w_output_8da8w-seq_4096.bundle`（約 880MB）は
Git に含めていません。サイズが GitHub の 1 ファイル 100MB 制限を超えるためです。
`.gitignore` で除外してあります。

このファイルが無くてもアプリはビルド・起動でき、LFM 以外のモデルは普通に使え
ます。同梱モデルを使うときだけ、LFM2.5-1.2B-JP を Leap SDK の変換ツールで
書き出し、`ChMateiOS/LocalLFM.swift` の `resourceName` と同じ名前で
`ChMateiOS/` の直下に置いてください。名前が違うと読み込み時に
「同梱LFM2.5-1.2B-JPモデルが見つかりません」と表示されます。

## ビルド（Windows / macOS デスクトップ）

`recovered-app/` は配布パッケージから取り出した Electron 版のソースです。

```sh
cd recovered-app
npm install
npx electron .
```

Electron 本体は依存に含めていないので、`npx electron` で取得するか、開発用に
`npm install --save-dev electron` で入れてください。依存は `he`、`iconv-lite`、
`react`、`react-dom`、`lucide-react` です。

配布パッケージを作る設定（electron-builder など）は含んでいません。必要なら
別途追加してください。

Windows ではレス本文の文字コードに CP932 を使うため `iconv-lite` で変換します。
macOS で AI を使う場合、既定の Core ML バックエンドはネイティブ実行ファイルを
必要とします。このリポジトリには含めていないので、Ollama バックエンドを選ぶか、
`native/coreml/` を用意してください。

## AI の準備

生成モデルは 3 系統あります。用途に応じて設定画面で選びます。

| モデル | 実行場所 | 用途 |
| --- | --- | --- |
| DeepSeek | クラウド（`api.deepseek.com`） | API キーを登録して使う。iPad でも動く |
| Ollama の各モデル | ローカル | 標準。日本語の自然さを優先する |
| LFM 1.2B | アプリ内 | オフライン用。複雑な論点は苦手 |

Ollama のモデルは次のタグを使います。

| タグ | 待ち受けポート | 備考 |
| --- | --- | --- |
| `qwen3:4b-instruct-2507-q4_K_M` | 11435 | 標準。日本語と指示追従のバランスが良い |
| `chmate-netslang:q4` | 11435 | Qwen3 4B に 5ch 文体の LoRA を載せたもの |
| `gemma3:4b-it-q4_K_M` | 11435 | 比較用。やわらかい日本語になりやすい |
| `qwen3.5:2b` | 11434 | 軽いが誤読が残る |
| `qwen2.5:3b` | 11434 | 比較用 |

アプリは 11435 と 11434 の 2 つのポートを見ます。11435 はメモリを節約するため
補助インスタンスとして起動する想定で、`scripts/run-local.command` が面倒を見ます。
ポート番号はアプリ側では固定です。変更する場合は
`ChMateiOS/AIBackend.swift` の `OllamaQwen` も合わせてください。

DeepSeek は設定画面から API キーを登録すると選べるようになります。キーは
アプリに埋め込まず、Keychain（iPad と署名済み Mac）または UserDefaults に
保存します。入力したレスと生成結果は DeepSeek のサーバーへ送信されます。

## 起動

ビルド済みの Mac Catalyst アプリを `~/Applications` へ置き、補助 Ollama を
起動してアプリを開きます。

```sh
./scripts/run-local.command
```

既定と違う場所を使うときは環境変数で上書きできます。

| 変数 | 既定値 |
| --- | --- |
| `CHMATE_BUILD_DIR` | `<リポジトリ>/.build-smb/DerivedData` |
| `CHMATE_MODEL_DIR` | リポジトリの隣の `chmate-models` |
| `CHMATE_NETSLANG_DIR` | リポジトリの隣の `netslang-chat` |
| `CHMATE_APP_DIR` | `~/Applications` |
| `CHMATE_OLLAMA_PORT` | `11435` |

アプリ本体を `~/Applications` へコピーするのは、外部ボリューム上からの直接起動が
macOS 側で止まるためです。スクリプトは起動と同時に、設定で選んでいるモデルを
バックグラウンドで先読みします。`CHMATE_NETSLANG_DIR` の辞書が書き換わって
いれば、配置先アプリの同梱辞書も更新してから起動します。

## テスト

Python 3 で動く検証スクリプトを `tests/` に置いています。いずれも 5ch への
投稿は行いません。

```sh
# 辞書の一致が元の Python 版と同じか
CHMATE_NETSLANG_DIR=<netslang-chat の場所> \
  python3 tests/netslang-dictionary-parity.py

# プロンプト組み立て・校閲・辞書 RAG・文末の重なりの回帰
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 tests/ai-generation-regression.py

# Electron 版の書き込み確認まわりのテスト
node tests/post-confirmation.test.cjs

# 生成の品質評価（Ollama が必要）
python3 tests/ai-quality-eval.py --model qwen3:4b-instruct-2507-q4_K_M
```

`tests/netslang-dictionary-parity.py` は Swift 版と Python 版へ同じ文を投げ、
拾った語が一致するかを照合します。`netslang-chat` の場所は環境変数
`CHMATE_NETSLANG_DIR` で指定します。

`tests/ai-quality-eval.py` の評価用レスは
`tests/fixtures/quality-eval-cases.json` です。公開スレから数件を出典 URL つきで
引用した小さな固定セットで、投稿は行いません。生成のたびに結果が変わるため、
数値は目安として見てください。プロンプト変更の前後を比べるときは、変更前の
`AIViews.swift` を `.build-smb/quality-eval/AIViews.before.swift` に置いて
`--baseline` を付けます。

## ディレクトリ構成

```
ChMateiOS/            Swift 版のソース（Mac Catalyst と iPad で共通）
ChMateiOS.xcodeproj/  Xcode プロジェクトと Swift Package の解決結果
recovered-app/        Electron 版のソース
  electron/           メインプロセス（通信、解析、AI、画像）
  dist/               画面（HTML / CSS / JS）
docs/                 モデル構成、移植メモ
scripts/              起動スクリプト
tests/                回帰テストと品質評価
  fixtures/           品質評価に使うレスの固定セット
repair-build/         macOS 用の app.asar 再梱包スクリプト
```

`repair-build/` はビルド済みの `ChMate.app` の中身を `recovered-app/` の内容で
差し替えるためのローカル用スクリプトです。生成物は `.gitignore` で除外し、
`repack.py` だけを残しています。

## 個人情報と API キー

- API キーはソースに含めていません。利用者が設定画面から入力します。
- DeepSeek のキーは Keychain、または UserDefaults に保存します。
- ビルド成果物、モデル、`node_modules`、Xcode の個人設定
  （`xcuserdata/`）は Git の対象外です。
- ボリュームの絶対パスやホスト名はソースに書きません。環境変数
  （`CHMATE_*`）で指定する形にしています。

## 注意

- 5ch への書き込みは利用者自身の操作で行う前提です。リポジトリのテストは
  読み取りと生成だけを扱い、投稿しません。
- 辞書には読み専用の語（`risk` が medium / high）が含まれます。意味の説明には
  使いますが、書き込みには使わないようプロンプトで指示しています。
- `docs/geschar-features.md` は他アプリの構成を調べて参考にした記録です。

## 連絡先

不具合の報告や質問は softwareclone@proton.me までお願いします。

## ライセンス

このリポジトリのライセンスは [LICENSE](LICENSE)（MIT）です。ただし次のものは
含みません。それぞれの提供元の条件に従ってください。

- 同梱モデル用の `LFM2.5-1.2B-JP`（Liquid AI）
- Leap SDK
- Electron 版の npm 依存（`react`、`react-dom`、`lucide-react`、`he`、
  `iconv-lite`）
- 5ちゃんねるの名称、および各板のコンテンツ
