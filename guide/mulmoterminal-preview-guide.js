// Markdown プレビュー専用。コピー処理には触れず、親のガイドのオン／オフに従う。
// 中継が固定のコードだけを、上流の nonce 付きで差し込む。本文やパスは埋め込まない。
(() => {
  "use strict";
  let on = false;
  let bubble = null;
  let muted = null;
  let savedTitle = null;
  function hide() {
    if (bubble) bubble.style.display = "none";
    if (muted && !muted.hasAttribute("title") && savedTitle !== null) muted.setAttribute("title", savedTitle);
    muted = null;
    savedTitle = null;
  }
  function show(event) {
    if (!on || !(event.target instanceof Element)) return;
    const button = event.target.closest("button");
    const pre = button?.previousElementSibling;
    if (!pre?.matches("pre[data-code-block]")) { hide(); return; }
    if (muted !== button) {
      hide();
      muted = button;
      savedTitle = button.getAttribute("title");
      button.removeAttribute("title");
    }
    if (!bubble) {
      bubble = document.createElement("div");
      bubble.id = "mtg-preview-bubble";
      bubble.style.cssText = "position:fixed;z-index:2147483646;box-sizing:border-box;max-width:min(300px,calc(100vw - 16px));padding:9px 11px;border-radius:8px;background:rgba(17,17,20,.96);color:#f2f2f5;font:12.5px/1.6 -apple-system,sans-serif;white-space:pre-line;overflow-wrap:anywhere;pointer-events:none;box-shadow:0 6px 24px #0005";
      bubble.textContent = "このコードブロックを、ファイルの内容からコピーします。\n貼りたいコマンドや文面があるときに。コピー後は通知が出ます。\n不可視文字がある・コピーできない場合は確認画面が開きます。";
      document.body.appendChild(bubble);
    }
    bubble.style.display = "block";
    const rect = bubble.getBoundingClientRect();
    bubble.style.left = `${Math.max(8, Math.min(event.clientX + 14, innerWidth - rect.width - 8))}px`;
    bubble.style.top = `${Math.max(8, Math.min(event.clientY + 18, innerHeight - rect.height - 8))}px`;
  }
  window.addEventListener("message", (event) => {
    if (event.source !== parent || event.data?.source !== "mulmo-preview-guide-host" || typeof event.data.on !== "boolean") return;
    on = event.data.on;
    if (!on) hide();
  });
  document.addEventListener("pointerover", show, { passive: true });
  document.addEventListener("mousemove", show, { passive: true });
  document.addEventListener("mouseleave", hide, { passive: true });
  document.addEventListener("click", hide, { passive: true });
  document.addEventListener("scroll", hide, { passive: true });
  parent.postMessage({ source: "mulmo-preview-guide-ready" }, "*");
})();
