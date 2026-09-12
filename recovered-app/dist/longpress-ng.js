(() => {
  const storageKey = "chmate_longpress_ng_ids";
  const delay = 600;
  let blocked = new Set();
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey) || "[]");
    if (Array.isArray(saved)) blocked = new Set(saved.filter(x => typeof x === "string"));
  } catch {}
  let timer = 0;
  let pressedButton = null;
  const suppressed = new WeakSet();

  const idFromButton = (button) => {
    const text = button?.textContent?.trim() || "";
    const match = text.match(/^ID:(.+?)\s+\d+$/);
    return match?.[1]?.trim() || "";
  };
  const hideBlocked = () => {
    document.querySelectorAll("article.post").forEach(article => {
      const idButton = article.querySelector(".post-meta button");
      if (idButton) idButton.title = "長押しでNG IDに追加して非表示";
      const id = idFromButton(idButton);
      article.classList.toggle("longpress-ng-hidden", Boolean(id && blocked.has(id)));
    });
  };
  const toast = (message) => {
    let item = document.querySelector(".longpress-ng-toast");
    if (!item) {
      item = document.createElement("div");
      item.className = "longpress-ng-toast";
      item.setAttribute("role", "status");
      document.body.appendChild(item);
    }
    item.textContent = message;
    item.classList.add("show");
    clearTimeout(Number(item.dataset.timer || 0));
    item.dataset.timer = String(setTimeout(() => item.classList.remove("show"), 2200));
  };
  const cancel = () => {
    clearTimeout(timer);
    timer = 0;
    pressedButton?.classList.remove("longpress-pending");
    pressedButton = null;
  };
  document.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    const button = event.target.closest("article.post .post-meta button");
    const id = idFromButton(button);
    if (!id) return;
    cancel();
    pressedButton = button;
    button.classList.add("longpress-pending");
    timer = setTimeout(() => {
      timer = 0;
      suppressed.add(button);
      blocked.add(id);
      localStorage.setItem(storageKey, JSON.stringify([...blocked]));
      const ngButton = Array.from(button.closest("article.post")?.querySelectorAll(".post-actions button") || [])
        .find(item => item.textContent.trim() === "NG ID");
      ngButton?.click();
      hideBlocked();
      navigator.vibrate?.(30);
      toast(`ID:${id} をNG登録し、非表示にしました`);
      button.classList.remove("longpress-pending");
      pressedButton = null;
    }, delay);
  }, true);
  for (const type of ["pointerup", "pointercancel", "pointerleave"]) {
    document.addEventListener(type, cancel, true);
  }
  document.addEventListener("click", (event) => {
    const button = event.target.closest("article.post .post-meta button");
    if (!button || !suppressed.has(button)) return;
    suppressed.delete(button);
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);
  document.addEventListener("contextmenu", (event) => {
    if (event.target.closest("article.post .post-meta button")) event.preventDefault();
  }, true);
  new MutationObserver(hideBlocked).observe(document.documentElement, { childList: true, subtree: true });
  hideBlocked();
})();
