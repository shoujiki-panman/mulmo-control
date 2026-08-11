#!/usr/bin/env node
// npx mulmo-control でメニューバーアプリを入れる（Issue #15）。
//
// なぜ npm 経由なのか。
//
// ブラウザで zip を落とすと macOS が隔離マーク（com.apple.quarantine）を付け、
// Gatekeeper がダブルクリックを止める。macOS 15 以降は右クリック → 開く の
// 抜け道も塞がれ、システム設定から許可させるしかない。「マルウェアの可能性が
// あります」と出るものを、利用者に押し切らせる作りにはしたくない。
//
// 隔離マークを付けるのはダウンロードしたアプリ（ブラウザ）であって、ファイル
// そのものの性質ではない。node が取ってきたものには付かないので、いまの自己
// 署名のままで普通に開く。Apple Developer Program（年 99 USD）は要らない。
//
// Claude Code も MulmoTerminal も同じ流儀で配っている。

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";

const REPO = "shoujiki-panman/mulmo-control";
const ZIP_URL = process.env.MULMO_CONTROL_ZIP_URL
  ?? `https://github.com/${REPO}/releases/latest/download/MulmoControl.zip`;
const APP_DEST = "/Applications/Mulmo Control.app";

const say = (s) => process.stdout.write(`${s}\n`);
const step = (s) => say(`\n▶ ${s}`);
const ok = (s) => say(`  ✓ ${s}`);
const die = (s) => { process.stderr.write(`\n✗ ${s}\n`); process.exit(1); };

const run = (cmd, args, opts = {}) =>
  execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...opts });

if (process.platform !== "darwin") die("Mulmo Control は macOS 専用です。");

const major = Number(run("sw_vers", ["-productVersion"]).trim().split(".")[0]);
if (Number.isFinite(major) && major < 14) {
  die(`この macOS では動きません。macOS 14 (Sonoma) 以降が必要です。`);
}

const work = mkdtempSync(join(tmpdir(), "mulmo-control-"));
process.on("exit", () => { try { rmSync(work, { recursive: true, force: true }); } catch {} });

step("アプリをダウンロード");
const zip = join(work, "MulmoControl.zip");
try {
  const res = await fetch(ZIP_URL, { redirect: "follow" });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  writeFileSync(zip, Buffer.from(await res.arrayBuffer()));
} catch (e) {
  die(`ダウンロードできませんでした（${e.message}）。回線を確認して、もう一度お試しください。`);
}
ok(`${(run("du", ["-h", zip]).split("\t")[0] || "").trim()}`);

step("展開して確認");
run("ditto", ["-x", "-k", zip, work]);
const src = join(work, "Mulmo Control.app");
if (!existsSync(join(src, "Contents/MacOS/MulmoControl"))) {
  die("ダウンロードした内容が壊れています。時間をおいて、もう一度お試しください。");
}
let version = "";
try {
  version = run("defaults", ["read", join(src, "Contents/Info.plist"), "CFBundleShortVersionString"]).trim();
} catch { /* 版が読めなくても入れられる */ }
ok(version ? `バージョン ${version}` : "取得できました");

step("Applications に入れる");
try {
  rmSync(APP_DEST, { recursive: true, force: true });
  run("ditto", [src, APP_DEST]);
} catch (e) {
  die(`/Applications に置けませんでした（${e.message}）。Mulmo Control を終了してから、もう一度お試しください。`);
}
// node が落としたものに隔離マークは付かないが、念のため落としておく。
try { run("xattr", ["-cr", APP_DEST]); } catch {}
try { run("codesign", ["--force", "--deep", "--sign", "-", APP_DEST]); } catch {}
ok(APP_DEST);

step("設定を書き出す");
const support = join(homedir(), "Library/Application Support/Mulmo Control");
mkdirSync(support, { recursive: true });
mkdirSync(join(homedir(), "Documents/Codex/SwiftBarLogs"), { recursive: true });
const q = (v) => `'${String(v).replaceAll("'", "'\\''")}'`;
const mulmoClaudeDir = process.env.MULMOCLAUDE_DIR ?? join(homedir(), "mulmoclaude");
writeFileSync(join(support, "app-info.env"), [
  `MULMO_CONTROL_REPO_URL=${q(`https://github.com/${REPO}.git`)}`,
  `MULMO_CONTROL_SOURCE_DIR=${q(join(support, "source"))}`,
  `MULMO_CONTROL_BRANCH=${q("main")}`,
  `MULMO_CONTROL_MULMOCLAUDE_DIR=${q(mulmoClaudeDir)}`,
  "",
].join("\n"));
// 「最新です」とはここで書かない。実際に入った版だけを事実として残し、判定は
// アプリの確認に任せる（Issue #31）。
writeFileSync(join(homedir(), "Documents/Codex/SwiftBarLogs/mulmo-control-self-update.json"),
  JSON.stringify({
    checkedAt: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    status: "unknown", installedVersion: version, latestVersion: "", detail: "確認中",
  }, null, 2) + "\n");
ok("app-info.env");

step("起動");
try { run("open", ["-a", APP_DEST]); ok("メニューバーに出ます"); }
catch { say("  起動できませんでした。Applications から手で開いてください。"); }

say(`
Mulmo Control を入れました。

画面いちばん上の帯の右のほう、時計や Wi-Fi が並んでいるあたりに
ターミナルの形をした >_ アイコンが増えています。クリックすると操作画面が開きます。

ウィンドウも Dock アイコンも出ません。見当たらないときは、メニューバーが
混んでいて隠れています。

MulmoTerminal がまだ入っていない場合は、開いた画面の 環境 タブから
インストール できます。`);
