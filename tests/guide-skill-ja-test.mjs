// 英語だったスキルの説明を訳して控える係を、偽の claude で実際に走らせる（Issue #226）。
//
// check.sh から `node tests/guide-skill-ja-test.mjs` で呼ぶ。スキルはすべて架空のもの。
//
// 1. 英語の判定が japanese-guard（本人の Mac の Stop フック）と同じ閾値
// 2. 英語でない説明・同梱スキルは訳させない
// 3. 失敗・時間切れ・英語のままの返事は捨てる（ガイドは原文を出す）
// 4. 控えがあれば claude を呼ばない
// 5. 1つの窓（10分）で訳させる本数に上限がある
// 6. claude に渡すのは説明の文だけで、道具を持たせない
// 7. 本物の中継を偽の HOME・偽の MulmoTerminal で立て、一覧を1バイトも変えずに流し、
//    訳を返す口が門番を通り、パスを返さないこと

import http from "node:http";
import net from "node:net";
import { spawn } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const MODULE = fileURLToPath(new URL("../scripts/mulmoterminal-guide-skill-ja.mjs", import.meta.url));
const PROXY = fileURLToPath(new URL("../scripts/mulmoterminal-guide-proxy.mjs", import.meta.url));
const ja = await import(MODULE);

let failures = 0;
const check = (ok, label) => {
  if (!ok) {
    failures += 1;
    process.stderr.write(`  ✗ ${label}\n`);
  }
};
const notes = [];

// ── 1. 英語の判定 ────────────────────────────────────────────
//
// japanese-guard.py の既定値（MIN_LATIN=25・RATIO=3）。ここに書いた値と、入っている Mac
// ではフック本体の値の両方と突き合わせる。
check(ja.MIN_LATIN === 25 && ja.RATIO === 3, `英語の閾値が japanese-guard と違います（${ja.MIN_LATIN} / ${ja.RATIO}）`);
const guard = join(homedir(), ".claude", "hooks", "japanese-guard.py");
if (existsSync(guard)) {
  const code = readFileSync(guard, "utf8");
  const minLatin = /JAPANESE_GUARD_MIN_LATIN", "(\d+)"/.exec(code)?.[1];
  const ratio = /JAPANESE_GUARD_RATIO", "([\d.]+)"/.exec(code)?.[1];
  check(Number(minLatin) === ja.MIN_LATIN && Number(ratio) === ja.RATIO,
    `英語の閾値が japanese-guard.py（${minLatin} / ${ratio}）と食い違っています`);
  notes.push("閾値は japanese-guard.py 本体と一致");
} else {
  notes.push("japanese-guard.py が無い Mac なので、フック本体との突き合わせは見ていません");
}
const L = (n) => "a".repeat(n);
const J = (n) => "あ".repeat(n);
check(ja.isEnglish(L(25)), "英字25字が英語と読まれません");
check(!ja.isEnglish(L(24)), "英字24字（閾値未満）が英語と読まれています");
check(!ja.isEnglish(L(30) + J(10)), "英字30・日本語10（ちょうど3倍）が英語と読まれています");
check(ja.isEnglish(L(30) + J(9)), "英字30・日本語9（3倍を超える）が英語と読まれません");
check(!ja.isEnglish(`\`\`\`\n${L(80)}\n\`\`\``), "コードブロックの中の英字を数えています");
check(!ja.isEnglish(`https://example.com/${L(80)}`), "URL の英字を数えています");
check(!ja.isEnglish(`[${L(10)}](https://example.com/${L(80)})`), "Markdown リンクの英字を数えています");
check(!ja.isEnglish("週報を型どおりに下書きし、PR を1周させて提出できるところまで作る。weekly report で使う。"),
  "日本語の説明が英語と読まれています");

// ── 偽の claude ──────────────────────────────────────────────
const work = mkdtempSync(join(tmpdir(), "mulmo-skill-ja-"));
const fakeClaude = join(work, "claude");
const callLog = join(work, "calls.log");
writeFileSync(fakeClaude, `#!/bin/sh
set -u
printf '%s\\n' "$*" >> "${callLog}"
cat > "${work}/last-stdin.txt"
case "\${FAKE_MODE:-ok}" in
  fail) exit 1 ;;
  slow) exec sleep 5 ;;
  english) echo "訳: This reply is still in English and should be thrown away by the proxy." ;;
  *) echo "架空のスキルの説明を日本語にしたものです。" ;;
esac
`);
chmodSync(fakeClaude, 0o755);
const calls = () => (existsSync(callLog) ? readFileSync(callLog, "utf8").trim().split("\n").filter(Boolean).length : 0);
const settle = async (translator) => {
  for (let i = 0; i < 100; i += 1) {
    if (translator.stats().idle) return;
    await new Promise((r) => setTimeout(r, 50));
  }
};

const EN = "Draft the example widget report from a template and keep it ready to hand in by Friday.";
const EN2 = "Collect the example gadget readings, compare them with last week, and point out anything odd.";

// ── 2. 訳させないもの ────────────────────────────────────────
{
  const cacheFile = join(work, "c1", "guide-skill-ja.json");
  const t = ja.createTranslator({ cacheFile, claude: fakeClaude });
  t.observe([
    { slug: "example-notes", description: "架空のメモを日付ごとに整理する。「メモ整理」で使う。" },
    { slug: "mulmoterminal-example", description: EN },
    { slug: "tiny", description: "Short one." },
  ]);
  await settle(t);
  check(calls() === 0, `英語でない説明・同梱スキル・短い説明で claude を呼んでいます（${calls()} 回）`);
  check(Object.keys(t.table()).length === 0, "訳させないはずの説明に訳が付いています");
}

// ── 訳す・控える ─────────────────────────────────────────────
const cacheFile = join(work, "c2", "guide-skill-ja.json");
{
  const t = ja.createTranslator({ cacheFile, claude: fakeClaude });
  t.observe([{ slug: "example-report", description: EN }, { slug: "example-report-copy", description: EN }]);
  await settle(t);
  check(calls() === 1, `英語の説明を訳すのに claude を ${calls()} 回呼んでいます（同じ説明は1回）`);
  check(t.table()[EN] === "架空のスキルの説明を日本語にしたものです。", "訳が表に載っていません");
  check(existsSync(cacheFile), "控えのファイルが書かれていません");

  // 6. 渡すのは説明の文だけ・道具を持たせない
  const stdin = readFileSync(join(work, "last-stdin.txt"), "utf8");
  check(stdin.includes(EN), "claude に説明の文が渡っていません");
  check(!stdin.includes(work) && !stdin.includes(homedir()) && !stdin.includes("SKILL.md"),
    "claude にパスやファイル名が渡っています");
  const args = readFileSync(callLog, "utf8").split("\n")[0];
  check(args.includes("-p") && args.includes("--tools") && args.includes("--safe-mode"),
    `claude に道具を外す指定がありません（${args}）`);
}

// ── 4. 控えがあれば呼ばない ──────────────────────────────────
{
  const before = calls();
  const t = ja.createTranslator({ cacheFile, claude: fakeClaude });
  t.observe([{ slug: "example-report", description: EN }]);
  await settle(t);
  check(calls() === before, "控えがあるのに claude を呼んでいます");
  check(t.table()[EN] === "架空のスキルの説明を日本語にしたものです。", "控えの訳が表に載っていません");
}

// ── 3. 失敗・時間切れ・英語のままは捨てる ────────────────────
for (const [mode, label] of [["fail", "失敗"], ["english", "英語のままの返事"], ["slow", "時間切れ"]]) {
  process.env.FAKE_MODE = mode;
  const t = ja.createTranslator({ cacheFile: join(work, `c-${mode}`, "x.json"), claude: fakeClaude, timeoutMs: 800 });
  const before = calls();
  t.observe([{ slug: "example-gadget", description: EN2 }]);
  await settle(t);
  check(calls() === before + 1, `${label}: claude を1回呼んでいません`);
  check(Object.keys(t.table()).length === 0, `${label}: 訳として表に載っています（原文を出すべき）`);
  t.observe([{ slug: "example-gadget", description: EN2 }]);
  await settle(t);
  check(calls() === before + 1, `${label}: 失敗したものを呼び直しています`);
}
delete process.env.FAKE_MODE;
{
  // claude が無い Mac: 何も起こさず、表は空（原文）
  const t = ja.createTranslator({ cacheFile: join(work, "c-none", "x.json"), claude: null });
  t.observe([{ slug: "example-report", description: EN }]);
  check(Object.keys(t.table()).length === 0, "claude が無いのに訳が出ています");
}

// ── 5. 上限 ──────────────────────────────────────────────────
{
  const t = ja.createTranslator({ cacheFile: join(work, "c3", "x.json"), claude: fakeClaude });
  const before = calls();
  const many = Array.from({ length: ja.MAX_PER_WINDOW + 3 }, (_, i) => ({
    slug: `example-${i}`,
    description: `${EN} Variant number ${i} of the made-up example skills.`,
  }));
  t.observe(many);
  await settle(t);
  check(calls() - before === ja.MAX_PER_WINDOW,
    `1つの窓で ${calls() - before} 本訳させています（上限 ${ja.MAX_PER_WINDOW}）`);
}

// ── 7. 本物の中継 ────────────────────────────────────────────
const freePort = () =>
  new Promise((resolve) => {
    const probe = net.createServer().listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
const get = (port, path, headers) =>
  new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, path, headers }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
    });
    req.on("error", reject);
    req.end();
  });

const SKILLS_BODY = JSON.stringify({
  cwd: "/Users/someone/example",
  skills: [
    { slug: "example-report", description: EN },
    { slug: "example-notes", description: "架空のメモを整理する。" },
  ],
});
const upstream = http.createServer((req, res) => {
  if (req.url.startsWith("/api/skills")) {
    res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
    res.end(SKILLS_BODY);
    return;
  }
  res.writeHead(404);
  res.end("upstream 404");
});
const upPort = await freePort();
const proxyPort = await freePort();
await new Promise((r) => upstream.listen(upPort, "127.0.0.1", r));
const fakeHome = mkdtempSync(join(tmpdir(), "mulmo-skill-ja-home-"));
writeFileSync(callLog, "");
const child = spawn(process.execPath, [PROXY], {
  env: {
    ...process.env, HOME: fakeHome, GUIDE_LISTEN: String(proxyPort), GUIDE_UPSTREAM_PORT: String(upPort),
    GUIDE_CLAUDE: fakeClaude,
  },
  stdio: ["ignore", "pipe", "pipe"],
});
await new Promise((resolve, reject) => {
  child.stdout.once("data", resolve);
  child.once("exit", (code) => reject(new Error(`中継が立ちませんでした（exit ${code}）`)));
});
const own = `127.0.0.1:${proxyPort}`;
try {
  const list = await get(proxyPort, "/api/skills?cwd=%2Fexample", { host: own });
  check(list.body === SKILLS_BODY, "中継が Skill の一覧を書き換えています");

  let table = {};
  for (let i = 0; i < 60 && table[EN] === undefined; i += 1) {
    await new Promise((r) => setTimeout(r, 100));
    const res = await get(proxyPort, "/__mulmo-guide/skill-ja", { host: own });
    table = JSON.parse(res.body).translations ?? {};
  }
  check(table[EN] === "架空のスキルの説明を日本語にしたものです。", "中継の口から訳が取れません");
  check(Object.keys(table).length === 1, "英語でない説明まで表に載っています");
  const raw = JSON.stringify(table);
  check(!raw.includes(fakeHome) && !raw.includes("/Users/") && !raw.includes("SKILL.md"), "訳の口がパスを返しています");
  check(existsSync(join(fakeHome, "Library", "Application Support", "Mulmo Control", "guide-skill-ja.json")),
    "控えが Mulmo Control の置き場所に書かれていません");

  const evil = await get(proxyPort, "/__mulmo-guide/skill-ja", { host: own, origin: "https://evil.example" });
  check(evil.status === 403, `よそのサイトからの訳の口が断られていません（${evil.status}）`);
  const rebind = await get(proxyPort, "/__mulmo-guide/skill-ja", { host: `evil.example:${proxyPort}` });
  check(rebind.status === 403, `Host を偽った訳の口が断られていません（${rebind.status}）`);
  // 訳の口は要求の中身でファイルを選ばない。パスらしきものを付けても、口としては答えない。
  const traversal = await get(proxyPort, "/__mulmo-guide/skill-ja?f=../../../../etc/passwd", { host: own });
  check(!traversal.body.includes("root:") && !traversal.body.includes("translations"),
    "訳の口が、要求に付けたパスで答えています");
} finally {
  child.kill();
  upstream.closeAllConnections();
  upstream.close();
}

if (failures > 0) {
  process.stderr.write(`${failures} 件、スキルの説明の訳が期待どおりに動いていません\n`);
  process.exit(1);
}
process.stdout.write(
  `英語判定は japanese-guard と同じ閾値（${ja.MIN_LATIN} / ${ja.RATIO}）・英語でないもの／同梱は訳さない・失敗／時間切れ／英語の返事は原文・控えがあれば呼ばない・上限 ${ja.MAX_PER_WINDOW} 本・渡すのは説明だけ・中継は一覧を変えず、訳の口は門番を通りパスを返さない（${notes.join("。")}）\n`,
);
