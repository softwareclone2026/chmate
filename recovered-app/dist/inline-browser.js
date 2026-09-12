(() => {
  const imageURL = /\.(?:png|jpe?g|gif|webp)(?:[?#].*)?$/i;
  const imgurURL = /^https:\/\/(?:www\.)?imgur\.com\/(?:a\/|gallery\/)?[A-Za-z0-9]+/i;
  const dialog = document.createElement("dialog");
  dialog.className = "inline-browser";
  dialog.innerHTML = `<header><div class="inline-browser-nav"><button type="button" data-action="back" title="戻る">←</button><button type="button" data-action="forward" title="進む">→</button><button type="button" data-action="reload" title="再読み込み">↻</button></div><input aria-label="ページURL" readonly><div class="inline-browser-actions"><button type="button" data-action="external">外部で開く</button><button type="button" data-action="close">閉じる</button></div></header><div class="inline-browser-loading">読み込み中…</div><webview partition="persist:chmate-inline" allowpopups></webview>`;
  document.body.appendChild(dialog);
  const webview = dialog.querySelector("webview");
  const address = dialog.querySelector("input");
  const loading = dialog.querySelector(".inline-browser-loading");

  const update = () => {
    try {
      address.value = webview.getURL() || address.value;
      dialog.querySelector('[data-action="back"]').disabled = !webview.canGoBack();
      dialog.querySelector('[data-action="forward"]').disabled = !webview.canGoForward();
    } catch {}
  };
  const close = () => {
    if (!dialog.open) return;
    dialog.close();
    webview.stop();
    webview.removeAttribute("src");
    window.chmate.setImageViewerOpen(false);
  };
  const open = (url) => {
    address.value = url;
    loading.hidden = false;
    if (!dialog.open) dialog.showModal();
    webview.src = url;
    window.chmate.setImageViewerOpen(true);
  };
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    close();
  });
  dialog.addEventListener("click", (event) => {
    const action = event.target.closest("[data-action]")?.dataset.action;
    if (action === "close") close();
    if (action === "back" && webview.canGoBack()) webview.goBack();
    if (action === "forward" && webview.canGoForward()) webview.goForward();
    if (action === "reload") webview.reload();
    if (action === "external") window.chmate.openExternal(webview.getURL() || address.value);
  });
  webview.addEventListener("did-start-loading", () => loading.hidden = false);
  webview.addEventListener("did-stop-loading", () => { loading.hidden = true; update(); });
  webview.addEventListener("did-navigate", update);
  webview.addEventListener("did-navigate-in-page", update);
  webview.addEventListener("did-fail-load", (event) => {
    if (event.errorCode === -3) return;
    loading.hidden = false;
    loading.textContent = `表示できませんでした: ${event.errorDescription}`;
  });
  window.chmate.onImageViewerClose(close);
  document.addEventListener("click", (event) => {
    const anchor = event.target.closest(".post-body a[href]");
    if (!anchor || imageURL.test(anchor.href) || imgurURL.test(anchor.href)) return;
    if (!/^https?:\/\//i.test(anchor.href)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    open(anchor.href);
  }, true);
})();
