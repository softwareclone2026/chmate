# ローカルAIモデルの構成

ChMate のレス生成は、Mac 上で動く Ollama のモデルを使います。
速度より日本語の適切さ・自然さを優先する方針です。

ビルドと起動の手順は [../README.md](../README.md) にまとめています。

## モデルの置き場所

| モデル | 保存先 | 待ち受けポート | 用途 |
| --- | --- | --- | --- |
| DeepSeek（deepseek-flash） | クラウド（api.deepseek.com） | なし | 追加のAPIキーで使う。iPadでも利用可 |
| Qwen3 4B Instruct 2507（Q4_K_M） | ローカルの `chmate-models` | 11435 | 標準。日本語と指示追従のバランスが良い |
| ネッスラ LoRA（`chmate-netslang:q4`） | ローカルの `chmate-models` | 11435 | Qwen3 4B に netslang の文体を追加学習したもの。辞書と併用する |
| Gemma 3 4B（Q4_K_M） | ローカルの `chmate-models` | 11435 | 比較用。やわらかい日本語になりやすい |
| Qwen 3.5 2B | Mac の `~/.ollama` | 11434 | 軽いが誤読が残る |
| Qwen 2.5 3B | Mac の `~/.ollama` | 11434 | 比較用 |
| LFM 1.2B | アプリ同梱 | なし | オフライン用。複雑な論点は苦手 |

4B モデルは 4bit 量子化で 2.5〜3.3GB です。メモリ 8GB の Mac でも、
同時に読み込むモデルを 1 つに絞れば動作します。

## ネッスラ LoRA（5ch 文体の追加学習）

netslang-chat で学習した LoRA アダプタ（`lora-deep-step100`）を GGUF へ変換し、
Ollama の `ADAPTER` で Qwen3 4B Instruct に載せたモデルです。文体は追加学習で
寄せ、意味の根拠は従来どおり辞書とプロンプトが担います。

| 項目 | 値 |
| --- | --- |
| アダプタ | `netslang-chat/models/chmate-netslang-q4.gguf`（29MB） |
| rank / alpha | 8 / 24（実効 `alpha/rank` = 3.0） |
| 対象 | 層 20〜35 の attention と MLP の 7 モジュール（112 テンソル） |
| 変換 | `netslang-chat/scripts/export_lora_gguf.py` |
| 登録 | `scripts/run-local.command` が未登録なら `ollama create` する |

mlx-lm は `lora_a`(in, r) / `lora_b`(r, out) をそのまま使いますが、llama.cpp は
`.lora_a`(r, in) / `.lora_b`(out, r) を期待します。変換スクリプトは転置して書き出し、
`adapter.lora.alpha` に実効倍率を入れます。llama.cpp 側は `alpha == 0` のときだけ
alpha を無視して倍率 1.0 にする実装なので、倍率を下げたいときは alpha を小さくします
（0 を指定すると逆に倍率が上がるので注意）。

このモデルを選ぶと、下書き生成の system プロンプトに netslang の compose 形式
（`NetSlangPrompts.composeSystem`）を渡します。学習時と同じ形に合わせるためです。
要約・分析は文体を指定しない処理なので、従来の system プロンプトのままです。
温度は 0.22 としています。0.35 では「〜の？だろ」のように語尾が重なる例が増えます。
文体ルールと後処理に加えて、この温度も重なりを減らすために効いています。

### 評価（2026-09-12）

`tests/ai-quality-eval.py` の4例（公開スレ由来、投稿なし）で、素の Qwen3 4B と
比べました。

| 設定 | 噛み合った返し | 語尾が重なった例 |
| --- | --- | --- |
| 素の Qwen3 4B Instruct（対策前） | 2/4 | 2/4 |
| ネッスラ LoRA（scale 3、対策前） | 2/4 | 2/4 |
| ネッスラ LoRA（scale 5、対策前） | 2/4 | 2/4 |
| ネッスラ LoRA（対策後） | 4/4 | 0/4 |

scale を上げると文体は濃くなりますが、語尾の重なりも増えます。scale 5 では
ループして崩れる例もありました（`netslang-alpha80` = scale 10 は明確に崩壊）。
そのため既定は scale 3 としています。

### 語尾の重なり（「〜ってことか？だろ」）

モデルは疑問文のうしろに語尾を足す癖があります。文体ルールの語尾例
（「〜だろ」「〜なんだが」「〜か？」）を、文末に必ず置くものとして扱うためです。
次の2段で止めています。

- `NetSlangPrompts.styleRule(.fiveCh)` と compose 形式の規則に「疑問文は
  「〜のか？」で終え、そのうしろに「〜だろ」を足さない」と明示する
- `AIService.removingDuplicatedTail` で、文末の「〜か？だろ」「〜の？なんだが」
  「〜じゃん？か？」だけを落とす（意味を変えずに落とせる重なりに限定）。疑問符と
  語尾のあいだに空白や零幅スペースを挟む例があるため、そこは許して落とす

文体ルールの書き換えだけでは「〜じゃん？か？」のような別の重なりが出て
止まりませんでした。プロンプトと後処理の併用で 4 例すべてが自然な文末になりました。

## DeepSeek（クラウドAI）

設定 →「DeepSeek（クラウドAI）」で API キーを登録すると、生成モデルとして
選べるようになります。キーを保存した時点で生成モデルは DeepSeek に切り替わります。

- エンドポイント: `https://api.deepseek.com/chat/completions`（OpenAI 互換）
- 認証: `Authorization: Bearer <APIキー>`
- モデル: `deepseek-flash`
- キーの保存先: Keychain を第一候補にし、同じセッションで読み戻せたかを確認してから
  採用します。読み戻せない場合は UserDefaults に退避し、設定画面の「保存先」に
  どちらへ保存したかを表示します
- 接続テスト: 設定画面の「接続テスト」で疎通とキーの有効性を確認できます

Mac 版のローカルビルドは ad-hoc 署名でエンタイトルメントを持たないため、
Keychain は `-34018`（errSecMissingEntitlement）で失敗し、UserDefaults に保存されます。
この場合キーはアプリの環境設定ファイルに平文で置かれます。暗号化して保管したい場合は
開発チームの証明書で署名したビルドにしてください。iPad 版は署名済みなので Keychain を使います。

入力したレス本文と生成結果は DeepSeek のサーバーへ送信されます。端末内だけで
生成したい場合は生成モデルに LFM を選んでください。iPad では Ollama が動かない
ため、選べるのは DeepSeek と LFM の 2 つです。

API キーは DeepSeek のプラットフォームで発行します。アプリには埋め込まず、
利用者が設定画面から入力する前提です。

## 起動

補助 Ollama の起動、アプリの配置、起動をまとめて行います。モデルは外部ボリュームに
置いたままでも構いません。

```sh
./scripts/run-local.command
```

補助 Ollama は `127.0.0.1:11435` で待ち受け、モデルは置いた場所からそのまま読み込み
ます。アプリ本体だけを `~/Applications/ChMate.app` にコピーするのは、外部ボリューム
上からの直接起動が macOS 側で止まるためです。

スクリプトは起動と同時に、設定で選んでいるモデルをバックグラウンドで先読み
します。冷えた状態からの読み込みには約 90 秒かかるため、最初の生成で待たされ
ないようにしています。先読みに失敗してもアプリの起動は止めません。

## ビルド

リポジトリのディレクトリでビルドします。インデックス生成は外部ボリュームと相性が
悪いため無効にします。

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

## ネットスラング辞書（読み書きの移植）

意味の根拠は辞書、文体はプロンプトという分担で組み立てています。
詳細は [netslang-port.md](netslang-port.md) を参照してください。

## 生成の方針

モデルを大きくするだけでは日本語は安定しません。現在は次の方針で組み立てています。

- 返信先（アンカー）とスレ冒頭だけを短く渡し、無関係なレスを混ぜない
- ID が空のレスを同一人物として扱わない
- 事実・数字・主語を変えない。資料にない統計や体験談を足さない
- 質問には質問として答える。相手が言っていない主張への反論を作らない
- 長さの下限を埋めるための水増しをしない
- 生成後の校閲は 1 回だけ行う

## 品質評価

2026-09-11 時点の実測結果です。`tests/ai-quality-eval.py` と同じ4例を使っています。

| モデル | 日本語の自然さ | 内容の適切さ | 1件あたり |
| --- | --- | --- | --- |
| Qwen3 4B Instruct | 常体の短文で自然 | 質問に回答。数字の誤読なし | 7〜10秒（初回のみ読み込みで約100秒） |
| Gemma 3 4B | 文法は正しいが丁寧語になりやすい | 5chの短文としては硬い | 20〜78秒 |
| Qwen 3.5 2B | 「5000万円」を「5000円」と誤読する例あり | 相手の発言を捏造して反論する例あり | 5〜15秒 |
| Qwen 2.5 3B | 単純な言い換えに寄る | 質問に答えず話題をそらす例あり | 4〜14秒 |

このため標準は **Qwen3 4B Instruct** にしています。同じ4例での生成例は次のとおりです。

- 「これ建物だけで5000ってこと？」→「建物だけじゃ5000万？土地代も入ってるのかな。」
- 「ラーメンと定食じゃ満足度が違いすぎる」→「満足度が違いすぎるって、何を基準にしたの？価格や味のデータないからね。」
- 「大和ハウスで家建てたなんて聞いた事ない」→「戸建やってないって言ってるけど、大和ハウスが注文住宅やってるって事実ある？」

モデルを大きくするだけでは足りず、渡す文脈と校閲の範囲を絞ることが効いています。

実際のアプリ生成コードを使って、公開スレの短い発言に対する返信を比べます。
投稿は行いません。

```sh
cd chMate-windows
python3 tests/ai-quality-eval.py \
  --model qwen3:4b-instruct-2507-q4_K_M \
  --cases .build-smb/quality-eval/cases.json
```

プロンプトと校閲の変更前後を比べる場合は `--baseline` を付けます。

```sh
python3 tests/ai-quality-eval.py \
  --model qwen3:4b-instruct-2507-q4_K_M \
  --cases .build-smb/quality-eval/cases.json --baseline
```
