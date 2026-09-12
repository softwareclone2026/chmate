const {
  app,
  BrowserWindow,
  ipcMain,
  session,
  dialog,
  shell,
  Menu,
  clipboard,
} = require("electron");
const path = require("node:path");
const fs = require("node:fs/promises");
const os = require("node:os");
const { pathToFileURL } = require("node:url");
const { createNetwork } = require("./network.cjs");
const { defaultBoards } = require("./core.cjs");
const { generate } = require("./ai.cjs");
let win;
let imageViewerOpen = false;
const devURL =
  !app.isPackaged && process.env.CHMATE_DEV_URL === "http://127.0.0.1:5173"
    ? process.env.CHMATE_DEV_URL
    : null;
const entry = path.join(__dirname, "../dist/index.html");
const trusted = (url) =>
  devURL ? new URL(url).origin === devURL : url === pathToFileURL(entry).href;
function handle(name, fn) {
  ipcMain.handle(name, async (event, ...args) => {
    if (
      event.sender !== win?.webContents ||
      event.senderFrame !== win.webContents.mainFrame ||
      !trusted(event.senderFrame.url)
    )
      throw new Error("許可されていない呼び出しです");
    return fn(...args);
  });
}
app.whenReady().then(() => {
  const network = createNetwork((url, options) =>
    session.defaultSession.fetch(url, options),
  );
  handle("boards:default", () => defaultBoards());
  handle("boards:menu", () => network.menu());
  handle("boards:threads", (board) => network.threads(board));
  handle("threads:posts", (thread) => network.posts(thread));
  handle("posts:send", (data) => network.post(data));
  handle("ai:generate", (data) => generate(data));
  handle("capture:save", async () => {
    const file = await dialog.showSaveDialog(win, {
      defaultPath: "chmate.png",
      filters: [{ name: "PNG", extensions: ["png"] }],
    });
    if (file.canceled || !file.filePath) return false;
    const image = await win.webContents.capturePage();
    await fs.writeFile(file.filePath, image.toPNG());
    return true;
  });
  handle("image:pick", async (kind) => {
    const result = await dialog.showOpenDialog(win, {
      title: kind === "photos" ? "写真ギャラリーから選択" : "画像ファイルを選択",
      defaultPath: kind === "photos" ? path.join(os.homedir(), "Pictures") : undefined,
      properties: ["openFile"],
      filters: [{ name: "画像", extensions: ["png", "jpg", "jpeg", "gif", "webp"] }],
    });
    return result.canceled ? null : result.filePaths[0] || null;
  });
  handle("image:resolve", async (value) => {
    const url = new URL(value);
    if (url.protocol !== "https:" || !/(^|\.)imgur\.com$/i.test(url.hostname))
      throw new Error("ImgurのURLではありません");
    if (/\.(?:png|jpe?g|gif|webp)(?:$|\?)/i.test(url.pathname)) return url.href;
    const response = await session.defaultSession.fetch(url.href, {
      headers: { "User-Agent": "Mozilla/5.0 Chrome/131 Safari/537.36" },
      redirect: "follow",
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw new Error(`画像情報を取得できませんでした (HTTP ${response.status})`);
    const html = await response.text();
    const match = html.match(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)/i)
      || html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);
    if (!match) throw new Error("Imgurページから画像を検出できませんでした");
    const imageURL = new URL(match[1].replace(/&amp;/g, "&"));
    if (imageURL.protocol !== "https:" || imageURL.hostname !== "i.imgur.com")
      throw new Error("Imgur以外の画像は表示できません");
    return imageURL.href;
  });
  handle("clipboard:write", (value) => {
    clipboard.writeText(String(value));
    return true;
  });
  handle("viewer:set-open", (value) => {
    imageViewerOpen = Boolean(value);
    return true;
  });
  handle("image:upload-web", async ({ source }) => {
    let filePath = source;
    if (source === "screenshot") {
      filePath = path.join(app.getPath("temp"), `chmate-${Date.now()}.png`);
      await fs.writeFile(filePath, (await win.webContents.capturePage()).toPNG());
    } else {
      const stat = await fs.stat(source);
      if (!stat.isFile() || stat.size > 20 * 1024 * 1024)
        throw new Error("画像は20MB以下のファイルを選択してください");
    }
    return new Promise(async (resolve, reject) => {
      const uploader = new BrowserWindow({
        width: 1100,
        height: 800,
        parent: win,
        title: "Imgur — 画像を投稿",
        webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true },
      });
      let settled = false;
      const finish = (fn, value) => {
        if (settled) return;
        settled = true;
        clearInterval(watcher);
        if (source === "screenshot") fs.unlink(filePath).catch(() => {});
        fn(value);
      };
      const detectURL = async () => {
        try {
          const value = await uploader.webContents.executeJavaScript(`(() => {
            const canonical = document.querySelector('meta[property="og:url"]')?.content;
            const candidates = [location.href, canonical, ...Array.from(document.querySelectorAll('input,a')).map(x => x.value || x.href)];
            return candidates.find(x => /^https:\\/\\/(?:i\\.)?imgur\\.com\\/(?:gallery\\/)?[A-Za-z0-9]{5,}(?:\\.[a-z]+)?$/i.test(x || '')) || '';
          })()`);
          if (value) {
            finish(resolve, value);
            uploader.close();
          }
        } catch {}
      };
      const watcher = setInterval(detectURL, 1000);
      uploader.on("closed", () =>
        finish(reject, new Error("Imgurの投稿画面を閉じました")),
      );
      uploader.webContents.on("did-finish-load", async () => {
        await detectURL();
        try {
          if (!uploader.webContents.debugger.isAttached())
            uploader.webContents.debugger.attach("1.3");
          const { root } = await uploader.webContents.debugger.sendCommand(
            "DOM.getDocument",
            { depth: -1, pierce: true },
          );
          const { nodeId } = await uploader.webContents.debugger.sendCommand(
            "DOM.querySelector",
            { nodeId: root.nodeId, selector: 'input[type="file"]' },
          );
          if (nodeId)
            await uploader.webContents.debugger.sendCommand(
              "DOM.setFileInputFiles",
              { nodeId, files: [filePath] },
            );
        } catch {}
      });
      try {
        await uploader.loadURL("https://imgur.com/upload");
      } catch (error) {
        finish(reject, error);
        uploader.close();
      }
    });
  });
  handle("external:open", async (value) => {
    const u = new URL(value);
    if (!["https:", "http:"].includes(u.protocol))
      throw new Error("HTTPリンクのみ開けます");
    await shell.openExternal(u.href);
  });
  win = new BrowserWindow({
    width: 1440,
    height: 940,
    minWidth: 960,
    minHeight: 640,
    title: process.platform === "darwin" ? "ChMate" : "ChMate Windows",
    backgroundColor: "#15191f",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: true,
      sandbox: true,
      webSecurity: true,
    },
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//.test(url)) shell.openExternal(url);
    return { action: "deny" };
  });
  win.webContents.on("will-attach-webview", (event, preferences, params) => {
    try {
      const url = new URL(params.src);
      if (!["https:", "http:"].includes(url.protocol)) throw new Error();
    } catch {
      event.preventDefault();
      return;
    }
    delete preferences.preload;
    preferences.nodeIntegration = false;
    preferences.contextIsolation = true;
    preferences.sandbox = true;
  });
  win.webContents.on("did-attach-webview", (_event, contents) => {
    contents.setWindowOpenHandler(({ url }) => {
      try {
        const parsed = new URL(url);
        if (["https:", "http:"].includes(parsed.protocol)) contents.loadURL(parsed.href);
        return { action: "deny" };
      } catch {
        return { action: "deny" };
      }
    });
  });
  win.webContents.on("will-navigate", (event) => event.preventDefault());
  win.on("close", (event) => {
    if (!imageViewerOpen) return;
    event.preventDefault();
    win.webContents.send("viewer:request-close");
  });
  session.defaultSession.setPermissionRequestHandler(
    (_wc, _permission, callback) => callback(false),
  );
  session.defaultSession.setPermissionCheckHandler(() => false);
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      ...(process.platform === "darwin" ? [{ role: "appMenu" }] : []),
      { label: "ファイル", submenu: [{ role: "quit", label: "終了" }] },
      {
        label: "編集",
        submenu: [
          { role: "undo" },
          { role: "redo" },
          { type: "separator" },
          { role: "cut" },
          { role: "copy" },
          { role: "paste" },
          { role: "selectAll" },
        ],
      },
      {
        label: "表示",
        submenu: [
          { role: "reload", label: "画面を再読み込み" },
          { role: "resetZoom" },
          { role: "zoomIn" },
          { role: "zoomOut" },
          { role: "togglefullscreen" },
        ],
      },
    ]),
  );
  if (devURL) win.loadURL(devURL);
  else win.loadFile(entry);
});
app.on("window-all-closed", () => app.quit());
