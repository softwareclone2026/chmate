(() => {
  const insertURL = (textarea, url) => {
    const value = textarea.value;
    const prefix = value && !value.endsWith("\n") ? "\n\n" : "";
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value").set;
    setter.call(textarea, value + prefix + url);
    textarea.dispatchEvent(new Event("input", { bubbles: true }));
    textarea.focus();
  };
  const attach = (textarea) => {
    if (textarea.dataset.imgurUploader) return;
    textarea.dataset.imgurUploader = "true";
    const box = document.createElement("section");
    box.className = "imgur-uploader";
    box.innerHTML = `<div class="imgur-title"><b>Imgur画像アップロード</b><small>Imgur公式サイトで投稿後、URLを本文へ挿入します</small></div><div class="imgur-controls"><button type="button" data-source="photos">写真ギャラリー</button><button type="button" data-source="file">ファイル選択</button><button type="button" data-source="screenshot">スクリーンショット</button></div><div class="imgur-status" role="status"></div>`;
    textarea.after(box);
    const status = box.querySelector(".imgur-status");
    box.addEventListener("click", async (event) => {
      const button = event.target.closest("button[data-source]");
      if (!button) return;
      const sourceKind = button.dataset.source;
      let source = "screenshot";
      try {
        if (sourceKind !== "screenshot") {
          source = await window.chmate.pickImage(sourceKind);
          if (!source) { status.textContent = "選択をキャンセルしました。"; return; }
        }
        box.querySelectorAll("button").forEach(b => b.disabled = true);
        status.textContent = "Imgurの投稿画面を開いています…";
        const url = await window.chmate.uploadImageViaWeb({ source });
        insertURL(textarea, url);
        status.textContent = "アップロード完了: " + url;
      } catch (error) {
        status.textContent = error?.message || String(error);
      } finally {
        box.querySelectorAll("button").forEach(b => b.disabled = false);
      }
    });
  };
  const scan = () => {
    for (const textarea of document.querySelectorAll('textarea[placeholder="本文を入力"]')) attach(textarea);
  };
  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
  scan();
})();
