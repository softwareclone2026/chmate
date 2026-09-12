(() => {
  const directImage = /\.(?:png|jpe?g|gif|webp)(?:[?#].*)?$/i;
  const imgurPage = /^https:\/\/(?:www\.)?imgur\.com\/(?:a\/|gallery\/)?[A-Za-z0-9]+(?:[/?#].*)?$/i;
  const resolved = new Map();
  let current = 0;
  let zoomed = false;

  const overlay = document.createElement("dialog");
  overlay.className = "image-viewer";
  overlay.innerHTML = `<header><span class="image-viewer-count"></span><div><button type="button" data-action="copy">URLコピー</button><button type="button" data-action="zoom">拡大</button><button type="button" data-action="close" aria-label="閉じる">×</button></div></header><button type="button" class="image-viewer-prev" data-action="prev" aria-label="前の画像">‹</button><div class="image-viewer-stage"><img alt="画像ブラウザ"></div><button type="button" class="image-viewer-next" data-action="next" aria-label="次の画像">›</button><footer class="image-viewer-url"></footer>`;
  document.body.appendChild(overlay);
  const viewerImage = overlay.querySelector("img");
  const count = overlay.querySelector(".image-viewer-count");
  const urlText = overlay.querySelector(".image-viewer-url");

  const images = () => Array.from(document.querySelectorAll("img.thumbnail,img.link-thumbnail"));
  const show = (index) => {
    const list = images();
    if (!list.length) return;
    current = (index + list.length) % list.length;
    const item = list[current];
    viewerImage.src = item.dataset.fullImage || item.src;
    urlText.textContent = item.dataset.sourceUrl || viewerImage.src;
    count.textContent = `${current + 1} / ${list.length}`;
    zoomed = false;
    viewerImage.classList.remove("zoomed");
    if (!overlay.open) overlay.showModal();
    document.body.classList.add("viewing-image");
    window.chmate.setImageViewerOpen(true);
  };
  const close = () => {
    if (overlay.open) overlay.close();
    viewerImage.removeAttribute("src");
    document.body.classList.remove("viewing-image");
    window.chmate.setImageViewerOpen(false);
  };
  overlay.addEventListener("cancel", (event) => {
    event.preventDefault();
    close();
  });
  window.chmate.onImageViewerClose(close);
  overlay.addEventListener("click", async (event) => {
    const action = event.target.closest("[data-action]")?.dataset.action;
    if (action === "close") close();
    if (action === "prev") show(current - 1);
    if (action === "next") show(current + 1);
    if (action === "zoom") {
      zoomed = !zoomed;
      viewerImage.classList.toggle("zoomed", zoomed);
      event.target.textContent = zoomed ? "全体表示" : "拡大";
    }
    if (action === "copy") {
      await window.chmate.copyText(urlText.textContent);
      event.target.textContent = "コピー済み";
      setTimeout(() => event.target.textContent = "URLコピー", 1200);
    }
    if (event.target === overlay) close();
  });
  document.addEventListener("keydown", (event) => {
    if (!overlay.open) return;
    if (event.key === "Escape") close();
    if (event.key === "ArrowLeft") show(current - 1);
    if (event.key === "ArrowRight") show(current + 1);
  });
  document.addEventListener("click", (event) => {
    const image = event.target.closest("img.thumbnail,img.link-thumbnail");
    if (!image) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    show(images().indexOf(image));
  }, true);

  const addThumbnail = async (anchor) => {
    if (anchor.dataset.imageScanned) return;
    anchor.dataset.imageScanned = "true";
    const href = anchor.href;
    if (!directImage.test(href) && !imgurPage.test(href)) return;
    if (anchor.parentElement?.querySelector(":scope > img.thumbnail, :scope > img.link-thumbnail")) return;
    try {
      let imageURL = directImage.test(href) ? href : resolved.get(href);
      if (!imageURL) {
        imageURL = await window.chmate.resolveImage(href);
        resolved.set(href, imageURL);
      }
      if (!anchor.isConnected) return;
      const img = document.createElement("img");
      img.className = "link-thumbnail";
      img.src = imageURL;
      img.dataset.fullImage = imageURL;
      img.dataset.sourceUrl = href;
      img.loading = "lazy";
      img.referrerPolicy = "no-referrer";
      img.alt = "リンク先画像のサムネイル";
      anchor.after(img);
    } catch {}
  };
  const scan = () => {
    document.querySelectorAll(".post-body a[href]").forEach(addThumbnail);
    document.querySelectorAll("img.thumbnail").forEach(img => {
      img.dataset.fullImage ||= img.src;
      img.dataset.sourceUrl ||= img.closest("span")?.querySelector("a")?.href || img.src;
    });
  };
  new MutationObserver(scan).observe(document.documentElement, { childList: true, subtree: true });
  scan();
})();
