const he = require('he');
const { encodeFormValue } = require('./core.cjs');
function attrs(tag) {
  const out = {};
  for (const m of tag.matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g))
    out[m[1].toLowerCase()] = he.decode(m[2] ?? m[3] ?? m[4]);
  return out;
}
function confirmationBody(html, endpoint, original) {
  if (!/書きこみ＆クッキー確認|書き込み確認|投稿確認/.test(html)) return null;
  for (const m of html.matchAll(/<form\b([^>]*)>([\s\S]*?)<\/form\s*>/gi)) {
    const form = attrs(m[1]);
    if ((form.method || '').toLowerCase() !== 'post') continue;
    let action;
    try { action = new URL(form.action || endpoint, endpoint); } catch { continue; }
    const expected = new URL(endpoint);
    if (action.origin !== expected.origin || action.pathname !== expected.pathname) continue;
    if (action.search && action.search !== '?guid=ON') continue;
    const fields = [];
    for (const input of m[2].matchAll(/<input\b[^>]*>/gi)) {
      const a = attrs(input[0]);
      if (!a.name || !['hidden','submit'].includes((a.type || '').toLowerCase())) continue;
      if (!/^[\w-]{1,80}$/.test(a.name) || (a.value || '').length > 100000) continue;
      fields.push([a.name,a.value || '']);
    }
    if (!fields.length) continue;
    const originalFields = new Map(original.split('&').map(p => { const i=p.indexOf('='); return [p.slice(0,i),p.slice(i+1)]; }));
    // The server cannot change the destination or approved text.
    const protectedNames = new Set(['bbs','key','subject','FROM','mail','MESSAGE']);
    for (const [name,value] of fields) {
      if (protectedNames.has(name)) continue;
      originalFields.set(name,encodeFormValue(value));
    }
    return {url: action.href, body: [...originalFields].map(([k,v])=>`${k}=${v}`).join('&')};
  }
  return null;
}
module.exports={confirmationBody};
