// MulmoTerminal 画面ガイド（日本語）
//
// MulmoTerminal の画面に、カーソルを合わせると日本語の説明が出るようにする。
// **ブラウザ拡張は使わない**（Issue #207）。Mulmo Control が MulmoTerminal の前に
// 中継（scripts/mulmoterminal-guide-proxy.mjs）を立て、画面の HTML にだけこの
// ファイルを差し込む。「開く」から開いた画面で出る。
//
// 経緯: 最初は Tampermonkey のユーザースクリプトとして作ったが、本人は拡張を
// 入れない方針で、**Tampermonkey は一度も入っていなかった**。#202 で「拡張が
// 消えた」と書いたのは誤り。

(() => {
  "use strict";

  // Mulmo Control が立てる極小サーバー（Sources/GuideServer.swift）。
  // **ここのポートは check.sh が GuideServer.port と突き合わせている。**
  // 片方だけ変えると、画面は黙って出なくなるだけで誰も気づけない。
  const ENDPOINT = "http://127.0.0.1:34599/mt-guide";
  const POLL_MS = 5000;
  const STORE_KEY = "mt-hover-guide-on";

  // MulmoTerminal のポートは動く（既定 34567、`.env` の PORT、逃げた先の 3002…）。
  // だから **ポートでは判定しない。** 画面が自分で名乗っている印で決める。
  const isMulmoTerminal = () =>
    document.title === "mulmoterminal" ||
    document.querySelector('[data-testid="cell-header-main"], [data-testid="mulmo-menu-btn"]') !== null;

  // ── 説明文 ──────────────────────────────────────────────────
  //
  // 当てる先は **`data-testid` と `aria-label`** にする。見えている文字で
  // 当てると、上流が言い回しを変えた日に黙って外れる。印なら、消えたときは
  // 説明が出ないだけで、間違った説明は出ない。
  //
  // 知らない要素には何も出さない。埋めることより、嘘を出さないことを取る。
  const BY_TESTID = {
    "machine-load": "この Mac の混み具合。数字が大きいほど、ターミナルの反応が鈍くなります。",
    "cell-header-main": "このセルが何なのかの見出し。フォルダ・git の状態・モデル・使った量が1行に並びます。",
    "dir-icon": "このフォルダの目印。プロジェクトごとに色と絵を変えられます（設定は各フォルダの .mulmoterminal.json）。",
    "dir-badge-workspace": "このセルが開いているフォルダの名前。",
    "git-chip": "git の現在地。左からブランチ・未コミットの数・リモートとの差です。",
    "git-branch": "いるブランチ。",
    "git-dirty": "まだコミットしていない変更の数。",
    "git-ab": "リモートとの差。↓ は向こうが進んでいる数、↑ はこちらが進んでいる数。",
    "model-badge": "このセッションのモデルと、文脈の残り。ctx が減ってきたら会話を分けどきです。",
    "cell-usage": "このセッションで流れたトークン量（入力 ⇡ / 出力 ⇣）。",
    "cell-prompt": "いま走っている（または最後に送った）指示。",
    "cell-memo-edit": "このセッションに覚え書きを付けます。何をやらせている枠なのかを、あとから見て分かるように。",
    "cell-park-btn": "このセルを脇に置きます。閉じるのとは違い、会話も履歴も残ったままです。",
    "cell-dir": "開いているフォルダ。押すと別のフォルダに切り替えられます。",
    "term-conn-status": "画面とターミナルの繋がり具合。disconnected のままなら、セルを開き直します。",
    "mulmo-menu-btn": "このフォルダのスライドや図を Canvas に出します。",
    "cell-ask": "別のセルに話しかけます。向こうの最後のやり取りをこちらへ持ってくる、1往復だけ交換する、といったことができます。",
  };

  const BY_ARIA = {
    Views: "画面の切り替え。ターミナルの並び・コレクション・PR・ルーム・作業ログを行き来します。",
    "Grid view": "ターミナルを並べて見る画面。ここが本拠地です。",
    Collections: "集めたデータの画面。記事のネタ、健康、計画といった「1件1枚」の記録がここに出ます。",
    "Pull requests": "自分が出している PR の一覧。CI が落ちていればここで分かります。",
    Rooms: "複数のセッションで囲む円卓。1つの話題を何人かで話させたいときに。",
    Worklog: "開発の作業ログ。誰が何をしたかが wiki に溜まります。",
    "New terminal": "新しいターミナルを立てます。どのフォルダで、どのエージェントで始めるかをここで選びます。",
    "Grid cell ordering: manual (click for priority)": "セルの並び順。手で並べるか、各フォルダに決めた優先度で並べるかを切り替えます。",
    Notifications: "溜まった知らせ。エージェントが待っている・終わった・CI が落ちた、などが入ります。",
    "Remote host": "スマホから使えるかどうか。繋がっていれば、外出先から同じセッションを覗けます。",
    Settings: "設定。テーマ・音・キーボード・エージェントの選び方をここから。",
    "Move terminal left": "このセルを左へ動かします。",
    "Move terminal right": "このセルを右へ動かします。",
    "Expand terminal": "このセルだけを大きく開きます。",
    "Start a terminal in this directory": "同じフォルダでもう1本立てます。並行で別のことをやらせたいときに。",
    "Close terminal": "このセルを閉じます。脇に置く（月のボタン）と違い、こちらは畳みます。",
    "Insert a file path": "ファイルの場所を指示欄に差し込みます。長いパスを打たずに済みます。",
    "Start voice input": "声で指示を入れます。",
    "Copy the last code block": "直前の返事にあったコードを、そのままクリップボードへ。",
    "Show activity timeline": "このセッションが何をしてきたかの時系列。",
    "Terminal input": "エージェントへの指示を書くところ。送り方（Enter か Shift+Enter か）は設定で変えられます。",
  };

  // 説明が付く印を持たない要素にも、上流が英語の説明を持たせていることがある。
  // その場合は**英語をそのまま残す**。訳が無いことと、訳を捏造することは違う。

  // ── 状態 ────────────────────────────────────────────────────
  //
  // 既定は ON。Mulmo Control 側の既定（UserDefaults 未設定 = ON）と揃える。
  // 揃っていないと、アプリを入れた瞬間に画面が変わったように見える。
  let on = localStorage.getItem(STORE_KEY) !== "0";
  let bubble = null;

  const save = () => localStorage.setItem(STORE_KEY, on ? "1" : "0");

  /** Mulmo Control に従う。居なければ（繋がらなければ）自分の記憶で動く。 */
  async function follow() {
    try {
      const res = await fetch(ENDPOINT, { cache: "no-store" });
      if (!res.ok) return;
      const body = await res.json();
      if (typeof body.on === "boolean" && body.on !== on) {
        on = body.on;
        save();
        paint();
      }
    } catch {
      // アプリが止まっているだけ。単体で動き続ける。
    }
  }

  // ── 吹き出し ────────────────────────────────────────────────
  function ensureBubble() {
    if (bubble !== null) return bubble;
    bubble = document.createElement("div");
    bubble.id = "mtg-bubble";
    bubble.style.cssText = [
      "position:fixed",
      "z-index:2147483646",
      "max-width:280px",
      "padding:8px 10px",
      "border-radius:8px",
      "background:rgba(17,17,20,0.96)",
      "color:#f2f2f5",
      "font:12.5px/1.6 -apple-system,BlinkMacSystemFont,'Hiragino Sans',sans-serif",
      "box-shadow:0 6px 24px rgba(0,0,0,0.35)",
      "pointer-events:none",
      "display:none",
    ].join(";");
    document.body.appendChild(bubble);
    return bubble;
  }

  /** その要素に当てる説明。無ければ null（何も出さない）。 */
  function explain(el) {
    const node = el.closest("[data-testid],[aria-label]");
    if (node === null) return null;
    const byId = BY_TESTID[node.getAttribute("data-testid") ?? ""];
    if (byId !== undefined) return byId;
    return BY_ARIA[node.getAttribute("aria-label") ?? ""] ?? null;
  }

  function show(text, x, y) {
    const box = ensureBubble();
    box.textContent = text;
    box.style.display = "block";
    // 画面の外へはみ出さない。右端と下端で折り返す。
    const rect = box.getBoundingClientRect();
    const left = Math.min(x + 14, window.innerWidth - rect.width - 8);
    const top = y + rect.height + 24 > window.innerHeight ? y - rect.height - 12 : y + 18;
    box.style.left = `${Math.max(8, left)}px`;
    box.style.top = `${Math.max(8, top)}px`;
  }

  const hide = () => {
    if (bubble !== null) bubble.style.display = "none";
  };

  function onMove(event) {
    if (!on) return;
    const text = event.target instanceof Element ? explain(event.target) : null;
    if (text === null) {
      hide();
      return;
    }
    show(text, event.clientX, event.clientY);
  }

  // ── 「?」ボタン ─────────────────────────────────────────────
  //
  // Mulmo Control を入れていない人でも切れるように、画面側にも口を残す。
  function mountToggle() {
    const button = document.createElement("button");
    button.id = "mtg-toggle";
    button.type = "button";
    button.textContent = "?";
    button.style.cssText = [
      "position:fixed",
      "right:14px",
      "bottom:14px",
      "z-index:2147483647",
      "width:28px",
      "height:28px",
      "border-radius:50%",
      "border:none",
      "cursor:pointer",
      "font:600 14px/1 -apple-system,sans-serif",
    ].join(";");
    button.addEventListener("click", () => {
      on = !on;
      save();
      paint();
      if (!on) hide();
    });
    document.body.appendChild(button);
    return button;
  }

  function paint() {
    const button = document.getElementById("mtg-toggle");
    if (button === null) return;
    button.style.background = on ? "#2f7df6" : "rgba(120,120,128,0.35)";
    button.style.color = on ? "#fff" : "#d8d8dd";
    button.title = on ? "画面ガイド: オン（押すと切る）" : "画面ガイド: オフ（押すと出す）";
  }

  function start() {
    if (!isMulmoTerminal()) return;
    mountToggle();
    paint();
    document.addEventListener("mousemove", onMove, { passive: true });
    document.addEventListener("mouseleave", hide, { passive: true });
    void follow();
    setInterval(follow, POLL_MS);
    // 別のウィンドウで切り替えたときに、戻ってきた瞬間に追いつく。
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) void follow();
    });
  }

  // 画面ができるまで待つ（SPA なので、最初の描画は空のことがある）。
  if (isMulmoTerminal()) start();
  else setTimeout(start, 1500);
})();
