#!/bin/bash
# ビルド済みの ChMate.app を ~/Applications へ置き、補助 Ollama を起動してアプリを開く。
# 既定の場所と違うときは環境変数で上書きする。
#   CHMATE_BUILD_DIR    ビルド出力（既定: <リポジトリ>/.build-smb/DerivedData）
#   CHMATE_MODEL_DIR    Ollama のモデル置き場（既定: リポジトリの隣の chmate-models）
#   CHMATE_NETSLANG_DIR netslang-chat の場所（既定: リポジトリの隣）
#   CHMATE_APP_DIR      アプリの配置先（既定: ~/Applications）
#   CHMATE_OLLAMA_PORT  補助 Ollama のポート（既定: 11435）
set -euo pipefail
PROJECT_DIR="$(cd -P "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${CHMATE_BUILD_DIR:-$PROJECT_DIR/.build-smb/DerivedData}"
MODEL_DIR="${CHMATE_MODEL_DIR:-$(dirname "$PROJECT_DIR")/chmate-models}"
NETSLANG_REPO="${CHMATE_NETSLANG_DIR:-$(dirname "$PROJECT_DIR")/netslang-chat}"
NETSLANG_TAG="chmate-netslang:q4"
NETSLANG_GGUF="$NETSLANG_REPO/models/chmate-netslang-q4.gguf"
BASE_TAG="qwen3:4b-instruct-2507-q4_K_M"
SOURCE_APP="$BUILD_DIR/Build/Products/Debug-maccatalyst/ChMate.app"
LOCAL_APP="${CHMATE_APP_DIR:-$HOME/Applications}/ChMate.app"
OLLAMA_PORT="${CHMATE_OLLAMA_PORT:-11435}"
OLLAMA_URL="http://127.0.0.1:$OLLAMA_PORT"
OLLAMA_BIN="$(command -v ollama || true)"
if [[ -z "$OLLAMA_BIN" && -x /opt/homebrew/bin/ollama ]]; then OLLAMA_BIN=/opt/homebrew/bin/ollama; fi
if [[ ! -d "$SOURCE_APP" || ! -d "$MODEL_DIR" || ! -x "$OLLAMA_BIN" ]]; then
    echo 'ビルド済みアプリ、Ollamaのモデル置き場、Ollama本体の場所を確認してください。' >&2
    echo "  アプリ:  $SOURCE_APP" >&2
    echo "  モデル:  $MODEL_DIR" >&2
    echo 'CHMATE_BUILD_DIR / CHMATE_MODEL_DIR で指定できます。' >&2
    exit 1
fi
if ! curl -fsS --max-time 2 "$OLLAMA_URL/api/tags" >/dev/null; then
    nohup env OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT" OLLAMA_MODELS="$MODEL_DIR" OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_NUM_PARALLEL=1 "$OLLAMA_BIN" serve > /tmp/chmate-ollama.log 2>&1 < /dev/null &
    ready=false
    for attempt in {1..20}; do
        if curl -fsS --max-time 1 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then ready=true; break; fi
        sleep 1
    done
    if [[ "$ready" != true ]]; then echo 'Ollamaを起動できませんでした。/tmp/chmate-ollama.logを確認してください。' >&2; exit 1; fi
fi
# netslang の LoRA アダプタを適用したモデルを、無ければ登録する。
# アダプタは netslang-chat 側の models/ に置いてあり、初回だけ登録すれば以後は
# Ollama のモデル置き場に残る。失敗しても他のモデルは使えるので、警告だけして続行する。
# 一覧はサーバーへ問い合わせる。CLI は読み込み中に失敗することがあるため使わない。
if ! /usr/bin/curl -fsS --max-time 5 "$OLLAMA_URL/api/tags" | /usr/bin/grep -q "$NETSLANG_TAG"; then
    if [[ -f "$NETSLANG_GGUF" ]]; then
        MODELEFILE="$(mktemp -t chmate-netslang)"
        printf 'FROM %s\nADAPTER %s\n' "$BASE_TAG" "$NETSLANG_GGUF" > "$MODELEFILE"
        if env OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT" OLLAMA_MODELS="$MODEL_DIR" "$OLLAMA_BIN" create "$NETSLANG_TAG" -f "$MODELEFILE" >> /tmp/chmate-ollama.log 2>&1; then
            echo "ネッスラ LoRA（${NETSLANG_TAG}）を登録しました。"
        else
            echo "ネッスラ LoRAの登録に失敗しました。/tmp/chmate-ollama.logを確認してください。" >&2
        fi
        rm "$MODELEFILE"
    else
        echo "ネッスラ LoRAのアダプタが見つかりません: $NETSLANG_GGUF" >&2
    fi
fi
# アプリが選んでいるモデルを先に読み込む。冷えた状態からは90秒ほどかかるので、
# ここで済ませておくと最初の生成が待たされない。失敗しても起動は止めない。
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)"
WARM_MODEL=""
if [[ -n "$BUNDLE_ID" ]]; then
    WARM_MODEL="$(/usr/bin/defaults read "$BUNDLE_ID" aiModelChoice 2>/dev/null || true)"
fi
case "$WARM_MODEL" in
    ""|"deepseek-flash"|"local-lfm") WARM_MODEL="$BASE_TAG" ;;
esac
nohup /usr/bin/curl -fsS --max-time 300 "$OLLAMA_URL/api/generate" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$WARM_MODEL\",\"prompt\":\"\",\"keep_alive\":\"30m\"}" \
    >> /tmp/chmate-ollama.log 2>&1 < /dev/null &
# 開いている下書きを捨てないよう、先にアプリを正規の手順で終了させる。
if /usr/bin/pgrep -x ChMate >/dev/null; then
    if [[ -n "$BUNDLE_ID" ]] && ! osascript -e "tell application id \"$BUNDLE_ID\" to quit"; then
        echo 'ChMateの下書きを保存し、開いているダイアログを閉じてから再実行してください。' >&2
        exit 1
    fi
    for attempt in {1..20}; do
        if ! /usr/bin/pgrep -x ChMate >/dev/null; then break; fi
        sleep 1
    done
    if /usr/bin/pgrep -x ChMate >/dev/null; then echo 'ChMateを終了してから再実行してください。' >&2; exit 1; fi
fi
mkdir -p "$(dirname "$LOCAL_APP")"
rsync -a "$SOURCE_APP/" "$LOCAL_APP/"
# 辞書はアプリ同梱のものを読みます。netslang-chat 側で語を足したときに反映される
# よう、書き換わっていたら配置先の Resources へ写してから起動します。
NETSLANG_DICT="$NETSLANG_REPO/data/slang.jsonl"
APP_DICT="$LOCAL_APP/Contents/Resources/slang.jsonl"
if [[ -f "$NETSLANG_DICT" && -f "$APP_DICT" ]] && ! /usr/bin/cmp -s "$NETSLANG_DICT" "$APP_DICT"; then
    if /bin/cp "$NETSLANG_DICT" "$APP_DICT"; then
        echo '辞書を netslang-chat の内容で更新しました。'
    else
        echo '辞書を配置先へ写せませんでした。同梱の辞書で起動します。' >&2
    fi
fi
open "$LOCAL_APP"
