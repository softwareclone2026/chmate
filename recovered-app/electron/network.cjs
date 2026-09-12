const {
  boardURL,
  parseMenu,
  parseSubject,
  parseDat,
  postBody,
  postResult,
} = require("./core.cjs");
const UA = `Monazilla/1.00 (ChMate/0.1.0 ${process.platform === "darwin" ? "macOS" : "Windows"})`;
const https = require('node:https');
function postRequest(url, headers, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, {method: 'POST', headers: {'User-Agent': UA, ...headers}}, (res) => {
      const chunks = []; let size = 0;
      res.on('data', chunk => {
        size += chunk.length;
        if (size > 16 * 1024 * 1024) req.destroy(new Error('受信サイズの上限を超えました'));
        else chunks.push(chunk);
      });
      res.on('end', () => {
        const bytes = Buffer.concat(chunks);
        const utf8 = /utf-?8|application\/json/i.test(String(res.headers['content-type'] || ''));
        const text = new TextDecoder(utf8 ? 'utf-8' : 'shift_jis').decode(bytes);
        const map = new Map(Object.entries(res.headers).map(([k,v]) => [k, Array.isArray(v) ? v.join(', ') : String(v || '')]));
        resolve({text, headers: {get: name => map.get(String(name).toLowerCase()) || null}});
      });
    });
    req.setTimeout(30000, () => req.destroy(new Error('投稿がタイムアウトしました')));
    req.on('error', reject);
    req.end(body);
  });
}
function allowedURL(value) {
  const u = new URL(value);
  if (
    u.protocol !== "https:" ||
    u.username ||
    u.password ||
    u.port ||
    !/(^|\.)5ch\.(io|net)$/.test(u.hostname)
  )
    throw new Error("接続先URLが許可されていません");
  return u.href;
}
async function request(fetcher, url, options = {}) {
  const signal = AbortSignal.timeout(30000);
  let current = allowedURL(url);
  for (let n = 0; n < 5; n++) {
    const response = await fetcher(current, {
      ...options,
      headers: { "User-Agent": UA, ...options.headers },
      redirect: "manual",
      credentials: "include",
      signal,
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      // Never replay a user's post on a redirect.
      if (options.method === "POST")
        throw new Error(
          "投稿先が転送されました。板URLを更新してから再確認してください。",
        );
      current = allowedURL(
        new URL(response.headers.get("location"), current).href,
      );
      continue;
    }
    if (!response.ok)
      throw new Error(
        `HTTP ${response.status} — サーバーから取得できませんでした`,
      );
    const reader = response.body.getReader();
    let size = 0;
    const chunks = [];
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 16 * 1024 * 1024) {
        await reader.cancel();
        throw new Error("受信サイズの上限を超えました");
      }
      chunks.push(Buffer.from(value));
    }
    const bytes = Buffer.concat(chunks);
    const utf8 = /utf-?8|application\/json/i.test(
      response.headers.get("content-type") || "",
    );
    return {
      text: new TextDecoder(utf8 ? "utf-8" : "shift_jis").decode(bytes),
      headers: response.headers,
    };
  }
  throw new Error("転送回数の上限を超えました");
}
function createNetwork(fetcher, poster = postRequest) {
  let pendingConfirmation;
  return {
    async menu() {
      let failure;
      for (const name of ["bbsmenu.json", "bbsmenu.html"])
        try {
          const { text } = await request(
            fetcher,
            `https://menu.5ch.io/${name}`,
          );
          const cats = parseMenu(text);
          if (cats.length) return cats;
          throw new Error("板メニューを解析できませんでした");
        } catch (e) {
          failure = e;
        }
      throw failure;
    },
    async threads(board) {
      const { text } = await request(
        fetcher,
        boardURL(board.url) + "subject.txt",
      );
      const items = parseSubject(text, board);
      if (!items.length && text.trim())
        throw new Error("スレッド一覧を解析できませんでした");
      return items;
    },
    async posts(thread) {
      if (!/^\d+$/.test(thread.key)) throw new Error("スレッドIDが不正です");
      const { text } = await request(
        fetcher,
        boardURL(thread.board.url) + `dat/${thread.key}.dat`,
      );
      const items = parseDat(text);
      if (!items.length && text.trim())
        throw new Error("DATを取得できませんでした");
      return items;
    },
    async post(data) {
      let body = postBody(data);
      const fingerprint = JSON.stringify([data.board.url,data.key,data.title,data.name,data.mail,data.message]);
      let postURL = `${new URL(boardURL(data.board.url)).origin}/test/bbs.cgi`;
      if (pendingConfirmation?.fingerprint === fingerprint && Date.now() < pendingConfirmation.expires) {
        body = pendingConfirmation.body;
        postURL = pendingConfirmation.url;
      }
      pendingConfirmation = undefined;
      const
        url = new URL(boardURL(data.board.url));
      const referer = data.key
        ? `${url.origin}/test/read.cgi/${url.pathname.split("/")[1]}/${data.key}/`
        : url.href;
      const response = await poster(postURL, {
        "Content-Type": "application/x-www-form-urlencoded",
        Referer: referer,
        "Content-Length": Buffer.byteLength(body),
      }, body);
      const result = postResult(response.text, response.headers);
      if (!result.success) {
        const confirmedBody = require('./post-confirmation.cjs').confirmationBody(response.text, `${url.origin}/test/bbs.cgi`, body);
        if (confirmedBody) {
          pendingConfirmation = {fingerprint, body: confirmedBody.body, url: confirmedBody.url, expires: Date.now() + 600000};
          result.message = '5chの投稿確認です。以下を確認し、同意する場合は同じ下書きの「送信する」を押してください。\n\n' + require('./core.cjs').plain(response.text);
        }
      }
      return result;
    },
  };
}
module.exports = { allowedURL, request, createNetwork };
