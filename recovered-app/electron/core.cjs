// Port of ChMateObjC/Services/Ch5chNetworkManager.m (parsing and CP932 posting).
const he = require("he");
const iconv = require("iconv-lite");
const POPULAR = {
  poverty: "greta",
  livejupiter: "eagle",
  newsplus: "asahi",
  mnewsplus: "hayabusa9",
  news4vip: "mi",
  ghard: "krsw",
  anime: "pug",
  ios: "fate",
  mac: "egg",
  jisaku: "egg",
  tech: "mevius",
  prog: "medaka",
  applism: "egg",
  morningcoffee: "kizuna",
};
function plain(value = "") {
  return he
    .decode(
      String(value)
        .replace(/<br\s*\/?\s*>/gi, "\n")
        .replace(/<[^>]*>/g, ""),
    )
    .trim();
}
function boardURL(value) {
  const u = new URL(value);
  if (
    !["https:", "http:"].includes(u.protocol) ||
    u.username ||
    u.password ||
    u.port ||
    !/(^|\.)5ch\.(io|net)$/.test(u.hostname)
  )
    throw new Error("5chの板URLを指定してください");
  u.protocol = "https:";
  // Same migration rule as the Objective-C implementation.
  u.hostname = u.hostname.replace(/\.5ch\.net$/, ".5ch.io");
  if (!/^\/[a-zA-Z0-9_]+\/$/.test(u.pathname) || u.search || u.hash)
    throw new Error("板URLの形式が正しくありません");
  return u.href;
}
function defaultBoards() {
  const names = {
    poverty: "ニュー速(嫌儲)",
    newsplus: "ニュース速報+",
    mnewsplus: "芸スポ速報+",
    news4vip: "ニュース速報(VIP)",
    livejupiter: "なんでも実況J",
    ios: "iOS",
    mac: "Mac",
    jisaku: "自作PC",
    tech: "プログラミング",
    anime: "アニメ",
    ghard: "ハード・業界",
  };
  return [
    {
      name: "標準の板（メニュー未取得）",
      boards: Object.entries(names).map(([id, name]) => ({
        id,
        name,
        category: "標準の板",
        url: `https://${POPULAR[id]}.5ch.io/${id}/`,
      })),
    },
  ];
}
function parseMenu(text) {
  const categories = [];
  const add = (cat, name, url) => {
    try {
      const normalized = boardURL(url);
      cat.boards.push({
        id: new URL(normalized).pathname.split("/")[1],
        name: plain(name),
        category: cat.name,
        url: normalized,
      });
    } catch {}
  };
  try {
    const json = JSON.parse(text);
    for (const c of json.menu_list || []) {
      if (!c.category_name || /特別|ツール/.test(c.category_name)) continue;
      const cat = { name: plain(c.category_name), boards: [] };
      for (const b of c.category_content || [])
        if (b.url && b.board_name) add(cat, b.board_name, b.url);
      if (cat.boards.length) categories.push(cat);
    }
  } catch {
    let cat;
    for (const m of text.matchAll(
      /<b\b[^>]*>([\s\S]*?)<\/b>|<a\b[^>]*href\s*=\s*["']?(https?:\/\/[^\s"'<>]+)["']?[^>]*>([\s\S]*?)<\/a>/gi,
    )) {
      if (m[1] !== undefined) {
        cat = { name: plain(m[1]), boards: [] };
        categories.push(cat);
      } else if (cat) add(cat, m[3], m[2]);
    }
  }
  return categories.filter((c) => c.boards.length);
}
function parseSubject(text, board, now = Date.now()) {
  const url = boardURL(board.url);
  return text.split(/\r?\n/).flatMap((line) => {
    const m = line.match(/^(\d+)\.dat<>(.*?)\s*\((\d+)\)\s*$/);
    if (!m) return [];
    const count = Number(m[3]);
    return [
      {
        id: `${url}${m[1]}`,
        key: m[1],
        board: { ...board, url },
        title: plain(m[2]),
        postCount: count,
        speed: Math.round(
          count / Math.max(0.1, (now - Number(m[1]) * 1000) / 86400000),
        ),
      },
    ];
  });
}
function parseDat(text) {
  return text.split(/\r?\n/).flatMap((line, i) => {
    const parts = line.split("<>");
    if (parts.length < 4) return [];
    const message = plain(parts[3]);
    return [
      {
        number: i + 1,
        name: plain(parts[0]) || "名無しさん",
        mail: plain(parts[1]),
        date: plain(parts[2]),
        id: parts[2].match(/ID:([^\s<>]+)/)?.[1] || "",
        message,
        anchors: [
          ...new Set(
            Array.from(message.matchAll(/>>(\d+)/g), (m) => Number(m[1])),
          ),
        ],
      },
    ];
  });
}
function encodeFormValue(value) {
  const normalized = Array.from(String(value))
    .map((ch) =>
      iconv.decode(iconv.encode(ch, "cp932"), "cp932") === ch
        ? ch
        : `&#${ch.codePointAt(0)};`,
    )
    .join("");
  return Array.from(iconv.encode(normalized, "cp932"), (b) =>
    /[A-Za-z0-9*_.-]/.test(String.fromCharCode(b))
      ? String.fromCharCode(b)
      : b === 32
        ? "+"
        : "%" + b.toString(16).toUpperCase().padStart(2, "0"),
  ).join("");
}
function postBody(data) {
  if (
    !data ||
    typeof data.message !== "string" ||
    !data.message.trim() ||
    data.message.length > 100000
  )
    throw new Error("本文を入力してください（最大100,000文字）");
  const url = boardURL(data.board.url);
  const bbs = new URL(url).pathname.split("/")[1];
  if (data.key !== undefined && !/^\d+$/.test(data.key))
    throw new Error("スレッドIDが不正です");
  if (!data.key && !(typeof data.title === "string" && data.title.trim()))
    throw new Error("スレッドタイトルを入力してください");
  const fields = {
    bbs,
    time: String(Math.floor(Date.now() / 1000)),
    FROM: data.name || "名無しさん＠お腹いっぱい。",
    mail: data.mail || "",
    MESSAGE: data.message.replace(/\r\n?|\n/g, "\r\n"),
    submit: data.key ? "書き込む" : "新規スレッド作成",
  };
  if (data.key) fields.key = data.key;
  else fields.subject = data.title;
  return Object.entries(fields)
    .map(([k, v]) => `${k}=${encodeFormValue(v)}`)
    .join("&");
}
function postResult(text, headers) {
  if (
    /^[1-9]\d*$/.test(headers?.get("x-resnum") || "") ||
    /書きこみました|書きこみが終わりました|<!-- _X:success -->/.test(text)
  )
    return { success: true };
  return {
    success: false,
    message:
      plain(text).slice(0, 1800) ||
      "投稿結果を確認できませんでした。再送前にスレッドを更新してください。",
  };
}
function applyNG(posts, rules, mode) {
  return posts.flatMap((post) => {
    const ng = rules.some(
      (r) =>
        r.enabled &&
        r.value &&
        (r.type === "word"
          ? post.message.includes(r.value)
          : r.type === "name"
            ? post.name.includes(r.value)
            : r.type === "id"
              ? post.id.toLowerCase() === r.value.toLowerCase()
              : false),
    );
    return ng
      ? mode === "hide"
        ? []
        : [
            {
              ...post,
              message: "あぼーん",
              name: "NG",
              id: "",
              anchors: [],
              masked: true,
            },
          ]
      : [post];
  });
}
module.exports = {
  plain,
  boardURL,
  defaultBoards,
  parseMenu,
  parseSubject,
  parseDat,
  encodeFormValue,
  postBody,
  postResult,
  applyNG,
};
