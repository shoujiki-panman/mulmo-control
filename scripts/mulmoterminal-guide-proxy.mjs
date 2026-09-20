// MulmoTerminal の前に立って、画面（HTML）にだけ日本語ガイドを差し込む中継（Issue #207）。
//
// 画面ガイドは最初 Tampermonkey のユーザースクリプトとして作ったが、本人は
// ブラウザ拡張を入れない方針だった。拡張なしで MulmoTerminal の画面に手を
// 入れる口は、MulmoTerminal 本体には無い（2026-09-20 に 5.3.0 で確認）。
// だから Mulmo Control が間に立つ。
//
// ── 守ること ─────────────────────────────────────────────────
//
// MulmoTerminal は**ターミナルそのもの**。握られればこの Mac のシェルを握られる。
//
// 1. **門番をしてから通す。** MulmoTerminal は、よそのサイトからの接続を
//    Origin で断っている。中継は上流に「いつもの localhost から来た」と見せる
//    ために Origin を書き換えるので、**書き換える前に自分で同じ門番をする**。
//    門番なしで書き換えると、ブラウザで開いたどのページでも
//    `127.0.0.1:<中継>` に WebSocket を張るだけでシェルを握れる（試作で実際に
//    この穴を作った。Issue #207）。
//    - Host は中継自身の名前（127.0.0.1 / localhost と中継のポート）だけ。DNS rebinding よけ
//    - Origin が付いていたら、中継自身の画面のときだけ。無い要求（curl など、
//      ブラウザではないもの）はブラウザの攻撃経路ではないので通す
// 2. **ループバックだけで待ち受ける。** LAN に開くと同じネットワークの誰でも入れる。
// 3. **触るのは HTML だけ。** API・WebSocket・SSE は1バイトも書き換えずに通す。
//
// check.sh はこの中継を偽の MulmoTerminal に当てて**実際に走らせ**、よそのサイトを
// 名乗る要求が断られることまで見ている。
//
// 環境変数:
//   GUIDE_LISTEN          待ち受けるポート（既定 34598。Swift の GuideProxy.port と揃える）
//   GUIDE_UPSTREAM_PORT   MulmoTerminal のポート（必須。既定は持たない・Issue #7）
//   GUIDE_JS              差し込むスクリプト（既定は同梱の ../guide/mulmoterminal-guide.js）

import http from "node:http";
import net from "node:net";
import zlib from "node:zlib";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const LOOPBACK = "127.0.0.1";
const LISTEN = Number(process.env.GUIDE_LISTEN ?? 34598);
// MulmoTerminal のポートは**既定を持たない。** ポートを持つのは
// mulmoterminal-agent-env と main.swift の mtPort の2か所だけ（Issue #7）。
// ここに数字を書くと、逃がしたつもりで中継だけ古いポートを向く。
const UPSTREAM_PORT = Number(process.env.GUIDE_UPSTREAM_PORT);
if (!Number.isInteger(UPSTREAM_PORT) || UPSTREAM_PORT <= 0) {
  process.stderr.write("guide proxy: GUIDE_UPSTREAM_PORT がありません（MulmoTerminal のポートを渡してください）\n");
  process.exit(2);
}
const GUIDE_JS = process.env.GUIDE_JS ?? fileURLToPath(new URL("../guide/mulmoterminal-guide.js", import.meta.url));
const GUIDE_PATH = "/__mulmo-guide.js";
const TAG = `<script src="${GUIDE_PATH}" defer></script>`;

// ── 門番 ─────────────────────────────────────────────────────

/** 中継自身の名前。ここに無い Host / Origin は通さない。 */
const OWN_HOSTS = new Set([`127.0.0.1:${LISTEN}`, `localhost:${LISTEN}`]);
const OWN_ORIGINS = new Set([...OWN_HOSTS].map((host) => `http://${host}`));

/** 通してよい要求か。理由を返す（通すなら null）。 */
export function refusal(headers) {
  if (!OWN_HOSTS.has((headers.host ?? "").toLowerCase())) return "host";
  const origin = headers.origin;
  if (origin !== undefined && !OWN_ORIGINS.has(origin.toLowerCase())) return "origin";
  return null;
}

// 門番を通ったものだけ、上流には「いつもの localhost から来た」と見せる。
const UPSTREAM_ORIGIN = `http://localhost:${UPSTREAM_PORT}`;

function upstreamHeaders(headers) {
  const out = { ...headers, host: `localhost:${UPSTREAM_PORT}` };
  if (out.origin) out.origin = UPSTREAM_ORIGIN;
  if (out.referer) out.referer = out.referer.replace(/^https?:\/\/[^/]+/, UPSTREAM_ORIGIN);
  return out;
}

// ── HTML への差し込み ────────────────────────────────────────

/** 圧縮されて返ってきたら戻す。identity を頼んでも守らない相手はいる。 */
function decode(body, encoding) {
  switch ((encoding ?? "").toLowerCase()) {
    case "gzip": return zlib.gunzipSync(body);
    case "br": return zlib.brotliDecompressSync(body);
    case "deflate": return zlib.inflateSync(body);
    default: return body;
  }
}

/** `</head>` の直前に差し込む。無ければ末尾に足す（出ないよりはいい）。 */
export function inject(html) {
  if (html.includes(TAG)) return html;
  return html.includes("</head>") ? html.replace("</head>", `${TAG}</head>`) : html + TAG;
}

function serveGuide(res) {
  // 毎回読む。アプリを更新しても、動き続けている中継が古いガイドを配らないように。
  let body;
  try {
    body = readFileSync(GUIDE_JS, "utf8");
  } catch {
    res.writeHead(404);
    res.end();
    return;
  }
  res.writeHead(200, { "content-type": "application/javascript; charset=utf-8", "cache-control": "no-store" });
  res.end(body);
}

function sendRewrittenHtml(upRes, res) {
  const chunks = [];
  upRes.on("data", (chunk) => chunks.push(chunk));
  upRes.on("end", () => {
    let html;
    try {
      html = inject(decode(Buffer.concat(chunks), upRes.headers["content-encoding"]).toString("utf8"));
    } catch {
      res.writeHead(502);
      res.end("MulmoTerminal の画面を読めませんでした");
      return;
    }
    const headers = { ...upRes.headers };
    delete headers["content-encoding"];
    delete headers["transfer-encoding"];
    headers["content-length"] = Buffer.byteLength(html);
    res.writeHead(upRes.statusCode ?? 200, headers);
    res.end(html);
  });
}

// ── 中継 ─────────────────────────────────────────────────────

const server = http.createServer((req, res) => {
  const why = refusal(req.headers);
  if (why !== null) {
    res.writeHead(403, { "content-type": "text/plain; charset=utf-8" });
    res.end(`refused (${why})`);
    return;
  }
  if (req.url === GUIDE_PATH) {
    serveGuide(res);
    return;
  }
  const wantsHtml = (req.headers.accept ?? "").includes("text/html");
  const headers = upstreamHeaders(req.headers);
  if (wantsHtml) headers["accept-encoding"] = "identity";
  const up = http.request(
    { host: LOOPBACK, port: UPSTREAM_PORT, method: req.method, path: req.url, headers },
    (upRes) => {
      if (!(upRes.headers["content-type"] ?? "").includes("text/html")) {
        res.writeHead(upRes.statusCode ?? 502, upRes.headers);
        upRes.pipe(res);
        return;
      }
      sendRewrittenHtml(upRes, res);
    },
  );
  up.on("error", () => {
    if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
    res.end("MulmoTerminal に届きません。Mulmo Control の「開く」から起動してください。");
  });
  req.pipe(up);
});

// WebSocket（ターミナルの入出力）。**ここが一番危ない入口**なので、門番は
// 同じものを必ず通す。通ったら最初の要求だけ Host / Origin を直し、
// あとは生のまま双方向に流す。中身は見ない。
server.on("upgrade", (req, socket, head) => {
  const why = refusal(req.headers);
  if (why !== null) {
    socket.end(`HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nrefused (${why})`);
    return;
  }
  const up = net.connect(UPSTREAM_PORT, LOOPBACK, () => {
    const headers = upstreamHeaders(req.headers);
    const lines = [`${req.method} ${req.url} HTTP/${req.httpVersion}`];
    for (const [key, value] of Object.entries(headers)) {
      for (const one of Array.isArray(value) ? value : [value]) lines.push(`${key}: ${one}`);
    }
    up.write(`${lines.join("\r\n")}\r\n\r\n`);
    if (head?.length) up.write(head);
    up.pipe(socket);
    socket.pipe(up);
  });
  const close = () => {
    up.destroy();
    socket.destroy();
  };
  up.on("error", close);
  socket.on("error", close);
});

server.on("error", (error) => {
  // ポートが塞がっていたら黙って諦める。呼ぶ側（Mulmo Control）は直接開く。
  process.stderr.write(`guide proxy: ${error.message}\n`);
  process.exit(1);
});

server.listen(LISTEN, LOOPBACK, () => {
  process.stdout.write(`guide proxy http://${LOOPBACK}:${LISTEN} -> ${LOOPBACK}:${UPSTREAM_PORT}\n`);
});
