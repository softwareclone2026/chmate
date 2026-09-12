const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
let active = false;
function generateCoreML(prompt, options = {}) {
  if (process.platform !== "darwin")
    throw new Error(
      "Core MLはmacOS専用です。WindowsではOllamaを選択してください。",
    );
  if (active)
    throw new Error("Core MLは生成中です。完了してから再実行してください。");
  const packaged =
    process.resourcesPath &&
    path.join(process.resourcesPath, "coreml", "ChMateCoreML");
  const executable =
    options.executable ||
    (packaged && fs.existsSync(packaged)
      ? packaged
      : path.join(__dirname, "../native/coreml/.build/release/ChMateCoreML"));
  const modelDirectory = path.join(
    os.homedir(),
    "Library",
    "Application Support",
    "ChMateCoreML",
    "qwen3.5-2b",
  );
  if (!fs.existsSync(executable))
    throw new Error(
      "Core ML実行ファイルがありません。npm run coreml:build を実行してください。",
    );
  if (!fs.existsSync(path.join(modelDirectory, "ready.json")))
    throw new Error(
      "Core MLモデルが未準備です。npm run coreml:setup を実行してください。Ollamaのモデルとは別のファイルが必要です。",
    );
  active = true;
  return new Promise((resolve, reject) => {
    const child = spawn(executable, [], { stdio: ["pipe", "pipe", "pipe"] });
    let output = "",
      diagnostics = "",
      timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, 600000);
    child.stdout.on("data", (chunk) => {
      output += chunk;
      if (output.length > 1024 * 1024) child.kill("SIGKILL");
    });
    child.stderr.on("data", (chunk) => {
      diagnostics = (diagnostics + chunk).slice(-2000);
    });
    child.stdin.on("error", () => {});
    child.on("error", (error) => {
      clearTimeout(timer);
      active = false;
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      active = false;
      if (timedOut)
        return reject(
          new Error(
            "Core MLが10分以内に完了しませんでした。初回のモデル準備やメモリ使用量を確認してください。",
          ),
        );
      try {
        const result = JSON.parse(output);
        if (code !== 0 || result.error)
          throw new Error(result.error || "Core ML実行エラー");
        if (typeof result.response !== "string" || !result.response.trim())
          throw new Error("Core MLから本文が返されませんでした");
        resolve(result.response.trim());
      } catch (error) {
        reject(
          new Error(
            output
              ? error.message
              : `Core MLの起動に失敗しました: ${diagnostics}`,
          ),
        );
      }
    });
    child.stdin.end(
      JSON.stringify({ prompt, prompts: options.prompts, modelDirectory }),
    );
  });
}
module.exports = { generateCoreML };
