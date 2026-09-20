// 画面ガイドの中継を、偽の MulmoTerminal に当てて実際に走らせる（Issue #207）。
//
// check.sh から `node tests/guide-proxy-test.mjs` で呼ぶ。**アプリと同じ1本
// （scripts/mulmoterminal-guide-proxy.mjs）を子プロセスで立てる。**
//
// いちばん大事なのは門番の検査。中継は上流に Origin を書き換えて渡すので、
// 門番が抜けると、ブラウザで開いた**どのページからでも**シェルを握れる。
// 試作で実際にその穴を作った。「通ること」より「断ること」を先に見る。

import http from "node:http";
import net from "node:net";
import os from "node:os";
import zlib from "node:zlib";
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const PROXY = fileURLToPath(new URL("../scripts/mulmoterminal-guide-proxy.mjs", import.meta.url));
const HTML = "<!doctype html><html><head><title>mulmoterminal</title></head><body>grid</body></html>";
const JSON_BODY = '{"ok":true,"bytes":"\\u00e9 keep exactly"}';
const GUIDE_BODY = "/* guide */ window.__guide = 1;";

let failures = 0;
const check = (ok, label) => {
  if (!ok) {
    failures += 1;
    process.stderr.write(`  ✗ ${label}\n`);
  }
};

/** 空いているポートを1つ借りる。 */
const freePort = () =>
  new Promise((resolve) => {
    const probe = net.createServer().listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });

// ── 偽の MulmoTerminal ──────────────────────────────────────
const seen = { host: [], origin: [], upgrades: 0 };

const upstream = http.createServer((req, res) => {
  seen.host.push(req.headers.host);
  if (req.headers.origin) seen.origin.push(req.headers.origin);
  if (req.url === "/api/config") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON_BODY);
    return;
  }
  if (req.url === "/gz") {
    // identity を頼まれても圧縮して返す、行儀の悪い相手
    res.writeHead(200, { "content-type": "text/html; charset=utf-8", "content-encoding": "gzip" });
    res.end(zlib.gzipSync(HTML));
    return;
  }
  res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
  res.end(HTML);
});

// WebSocket の代わりに、101 を返して受け取ったものをそのまま返す（エコー）
upstream.on("upgrade", (req, socket) => {
  seen.upgrades += 1;
  seen.host.push(req.headers.host);
  if (req.headers.origin) seen.origin.push(req.headers.origin);
  socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n");
  socket.on("data", (chunk) => socket.write(chunk));
});

// ── 要求を投げる道具 ────────────────────────────────────────

function get(port, path, headers) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, path, headers }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
    });
    req.on("error", reject);
    req.end();
  });
}

/** 生の Upgrade 要求を投げ、返事の1行目と、エコーが返ってきたかを返す。 */
function upgrade(port, headers) {
  return new Promise((resolve) => {
    const socket = net.connect(port, "127.0.0.1", () => {
      const lines = ["GET /ws HTTP/1.1", ...Object.entries(headers).map(([k, v]) => `${k}: ${v}`)];
      socket.write(`${lines.join("\r\n")}\r\n\r\n`);
    });
    let buffer = "";
    let sent = false;
    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      if (buffer.startsWith("HTTP/1.1 101") && buffer.includes("\r\n\r\n") && !sent) {
        sent = true;
        socket.write("keystroke-42");
      }
      if (buffer.includes("keystroke-42")) {
        socket.destroy();
        resolve({ status: buffer.split("\r\n")[0], echoed: true });
      }
    });
    socket.on("close", () => resolve({ status: buffer.split("\r\n")[0], echoed: buffer.includes("keystroke-42") }));
    socket.on("error", () => resolve({ status: "error", echoed: false }));
    setTimeout(() => {
      socket.destroy();
      resolve({ status: buffer.split("\r\n")[0] || "timeout", echoed: false });
    }, 3000);
  });
}

/** ループバック以外の自分のアドレス。無ければ null（その検査は飛ばす）。 */
function lanAddress() {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const entry of list ?? []) {
      if (entry.family === "IPv4" && !entry.internal) return entry.address;
    }
  }
  return null;
}

function connectsFrom(host, port) {
  return new Promise((resolve) => {
    const socket = net.connect(port, host, () => {
      socket.destroy();
      resolve(true);
    });
    socket.on("error", () => resolve(false));
    setTimeout(() => {
      socket.destroy();
      resolve(false);
    }, 1500);
  });
}

// ── 本番 ─────────────────────────────────────────────────────

const upPort = await freePort();
const proxyPort = await freePort();
await new Promise((resolve) => upstream.listen(upPort, "127.0.0.1", resolve));

const guideDir = mkdtempSync(join(tmpdir(), "mulmo-guide-"));
const guideJs = join(guideDir, "guide.js");
writeFileSync(guideJs, GUIDE_BODY);

const child = spawn(process.execPath, [PROXY], {
  env: { ...process.env, GUIDE_LISTEN: String(proxyPort), GUIDE_UPSTREAM_PORT: String(upPort), GUIDE_JS: guideJs },
  stdio: ["ignore", "pipe", "pipe"],
});
await new Promise((resolve, reject) => {
  child.stdout.once("data", resolve);
  child.once("exit", (code) => reject(new Error(`中継が立ちませんでした（exit ${code}）`)));
});

const own = `127.0.0.1:${proxyPort}`;
const ownOrigin = `http://${own}`;
const html = { host: own, accept: "text/html" };

try {
  // ① 門番: よそのサイトを名乗る WebSocket は断る（いちばん大事）
  const upgradesBefore = seen.upgrades;
  const evilWs = await upgrade(proxyPort, {
    Host: own, Origin: "https://evil.example", Upgrade: "websocket", Connection: "Upgrade",
  });
  check(evilWs.status.includes("403"), `よそのサイトを名乗る WebSocket が断られていません（${evilWs.status}）`);
  check(!evilWs.echoed, "よそのサイトからの打鍵が、ターミナルまで届いています");
  check(seen.upgrades === upgradesBefore, "よそのサイトからの WebSocket が、上流まで渡っています");

  // ② 門番: よそのサイトを名乗る HTTP も断る
  const evilHttp = await get(proxyPort, "/api/config", { host: own, origin: "https://evil.example" });
  check(evilHttp.status === 403, `よそのサイトを名乗る HTTP が断られていません（${evilHttp.status}）`);

  // ③ 門番: Host を偽った要求（DNS rebinding）は断る
  const rebind = await get(proxyPort, "/", { host: `evil.example:${proxyPort}`, accept: "text/html" });
  check(rebind.status === 403, `Host を偽った要求が断られていません（${rebind.status}）`);

  // ④ 自分の画面からの WebSocket は通り、打鍵が往復する
  const ownWs = await upgrade(proxyPort, {
    Host: own, Origin: ownOrigin, Upgrade: "websocket", Connection: "Upgrade",
  });
  check(ownWs.status.includes("101"), `自分の画面からの WebSocket が通りません（${ownWs.status}）`);
  check(ownWs.echoed, "WebSocket の打鍵が往復しません");

  // ⑤ 上流には「いつもの localhost」として渡っている
  check(seen.origin.includes(`http://localhost:${upPort}`), "上流に渡す Origin が書き換わっていません");
  check(!seen.origin.some((o) => o.includes("evil")), "よそのサイトの Origin が上流に渡っています");
  check(seen.host.every((h) => h === `localhost:${upPort}`), "上流に渡す Host が書き換わっていません");

  // ⑥ HTML にだけ差し込む
  const page = await get(proxyPort, "/terminals", html);
  check(page.body.includes('<script src="/__mulmo-guide.js" defer></script></head>'), "画面にガイドが差し込まれていません");
  const gz = await get(proxyPort, "/gz", html);
  check(gz.body.includes("/__mulmo-guide.js") && gz.body.includes("grid"), "圧縮された画面に差し込めていません");

  // ⑦ HTML 以外は1バイトも変えない
  const api = await get(proxyPort, "/api/config", { host: own });
  check(api.body === JSON_BODY, "API の中身が書き換わっています");

  // ⑧ ガイドそのものを配る
  const guide = await get(proxyPort, "/__mulmo-guide.js", { host: own });
  check(guide.status === 200 && guide.body === GUIDE_BODY, "ガイドのスクリプトを配れていません");

  // ⑨ ループバックだけで待ち受ける（LAN のアドレスからは入れない）
  const lan = lanAddress();
  if (lan !== null) {
    check(!(await connectsFrom(lan, proxyPort)), `LAN のアドレス（${lan}）から中継に入れます`);
  }
} finally {
  child.kill();
  upstream.close();
}

if (failures > 0) {
  process.stderr.write(`${failures} 件、中継が期待どおりに動いていません\n`);
  process.exit(1);
}
process.stdout.write("門番（よその WebSocket・よその HTTP・偽の Host）・往復・差し込み・素通し・ループバック限定すべて一致\n");
