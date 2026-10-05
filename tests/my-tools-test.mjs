// 自分で選んだスキル（GitHub）の入れ口を、使い捨ての git リポジトリと偽の HOME で実際に走らせる（Issue #229）。
//
// check.sh から `node tests/my-tools-test.mjs` で呼ぶ。リポジトリはすべて架空のもの。
// GitHub の代わりに、手元に作ったリポジトリを MULMO_MY_TOOLS_GITHUB で見せる。
//
// 1. 出どころの読み方（owner/repo・URL・/tree/…/フォルダ）と、`..`・別のホスト・`-` 始まりを弾くこと
// 2. 最新タグの選び方（semver の順・-beta などは取らない）と frontmatter の読み方
// 3. 直下と skills/<名前>/ に同じスキルがあれば skills/ の側を入れ、タグの後の途中のコミットは配らず、
//    点で始まる物とリンクを持ってこないこと
// 4. 入れる前の確かめ（preview）は何も書かないこと
// 5. 同じ名前のスキルが既にあれば上書きしないこと
// 6. 版の確認（新しいタグで update、タグが無いリポジトリは先頭のコミット）
// 7. 更新は手元で書き換えていない物だけ入れ替え、書き換えた物は触らないこと
// 8. 名前の綴りが危ないスキル・リポジトリの外を指すフォルダは入れず、スキルが複数あればフォルダを求めること
// 9. 外すと、入れたフォルダと控えが消えること（書き換えた物は --force のときだけ）
// 10. Codex が入っている HOME には Codex の置き場にも入れること
// 11. 壊れた控えを空とみなして書き直さないこと、追加・更新を重ねて走らせないこと
//     （錠は逐次ではなく、同時に5本走らせて入れられるのが1本だけであることまで見る）
// 12. 確かめたコミット・名前から変わった物と、正式版が無いタグ付きリポジトリは入れないこと
// 13. 点で始まる手元の変更も守り、複数の置き場・控えの保存が失敗したら元に戻すこと

import { execFileSync, spawn, spawnSync } from "node:child_process";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  symlinkSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT = fileURLToPath(new URL("../scripts/mulmo-my-tools.mjs", import.meta.url));
const tools = await import(SCRIPT);

let failures = 0;
let checks = 0;
const check = (ok, label) => {
  checks += 1;
  if (!ok) {
    failures += 1;
    process.stderr.write(`  ✗ ${label}\n`);
  }
};

const tmp = mkdtempSync(join(tmpdir(), "mulmo-my-tools-test-"));
const github = join(tmp, "github");
const GIT_ENV = {
  ...process.env,
  HOME: tmp,
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_AUTHOR_NAME: "test",
  GIT_AUTHOR_EMAIL: "test@example.invalid",
  GIT_COMMITTER_NAME: "test",
  GIT_COMMITTER_EMAIL: "test@example.invalid",
};
const git = (cwd, ...args) =>
  execFileSync("git", args, { cwd, env: GIT_ENV, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

function writeFiles(dir, files) {
  for (const [rel, body] of Object.entries(files)) {
    const path = join(dir, rel);
    mkdirSync(dirname(path), { recursive: true });
    if (typeof body === "object") symlinkSync(body.link, path);
    else writeFileSync(path, body);
  }
}

function commit(dir, files, tags = []) {
  writeFiles(dir, files);
  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", "change");
  for (const tag of tags) git(dir, "tag", tag);
}

function makeRepo(owner, repo, files, tags = []) {
  const dir = join(github, owner, repo);
  mkdirSync(dir, { recursive: true });
  git(dir, "-c", "init.defaultBranch=main", "init", "-q");
  commit(dir, files, tags);
  return dir;
}

const skillMd = (name, description = `${name} の説明です。`) =>
  `---\nname: ${name}\ndescription: ${description}\n---\n\n# ${name}\n`;

function newHome({ codex = false } = {}) {
  const home = mkdtempSync(join(tmp, "home-"));
  if (codex) mkdirSync(join(home, ".codex"));
  return home;
}

const runEnv = (home) => ({ ...process.env, HOME: home, MULMO_MY_TOOLS_GITHUB: `file://${github}`, GIT_CONFIG_NOSYSTEM: "1" });
const lastLine = (text) => text.trim().split("\n").pop() ?? "";

function run(home, ...args) {
  const result = spawnSync(process.execPath, [SCRIPT, ...args], { env: runEnv(home), encoding: "utf8" });
  return { code: result.status, out: result.stdout, err: result.stderr, last: lastLine(result.stderr) };
}

// 実物の CLI でファイル操作の失敗を再現する。製品側には検査専用の抜け道を作らない。
const faultPreload = join(tmp, "fail-rename.cjs");
writeFileSync(faultPreload, `
const fs = require("node:fs");
const { syncBuiltinESMExports } = require("node:module");
const rename = fs.renameSync;
let failed = false;
fs.renameSync = (from, to) => {
  if (!failed && ((process.env.TEST_RENAME_FROM && String(from) === process.env.TEST_RENAME_FROM) ||
                  (process.env.TEST_RENAME_TO && String(to) === process.env.TEST_RENAME_TO))) {
    failed = true;
    throw Object.assign(new Error("injected rename failure"), { code: "EACCES" });
  }
  return rename(from, to);
};
syncBuiltinESMExports();
`);

function runWithFailure(home, { from = "", to = "" }, ...args) {
  const result = spawnSync(process.execPath, ["--require", faultPreload, SCRIPT, ...args], {
    env: { ...runEnv(home), TEST_RENAME_FROM: from, TEST_RENAME_TO: to }, encoding: "utf8",
  });
  return { code: result.status, out: result.stdout, err: result.stderr, last: lastLine(result.stderr) };
}

function runAsync(home, ...args) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [SCRIPT, ...args], { env: runEnv(home) });
    let out = "";
    let err = "";
    child.stdout.on("data", (chunk) => (out += chunk));
    child.stderr.on("data", (chunk) => (err += chunk));
    child.on("close", (code) => resolve({ code, out, err, last: lastLine(err) }));
  });
}

const support = (home) => join(home, "Library", "Application Support", "Mulmo Control");
const recordOf = (home) => JSON.parse(readFileSync(join(support(home), "my-tools.json"), "utf8"));
const claudeSkill = (home, name) => join(home, ".claude", "skills", name);
const listDir = (dir) => (existsSync(dir) ? readdirSync(dir).sort() : []);

try {
  // ── 1. 出どころ ─────────────────────────────────────────────
  const parse = tools.parseSource;
  check(parse("writer/plain-ja")?.url === "https://github.com/writer/plain-ja", "owner/repo が読めません");
  check(parse("https://github.com/writer/plain-ja.git")?.repo === "plain-ja", ".git 付きの URL が読めません");
  check(parse("https://github.com/writer/plain-ja/")?.repo === "plain-ja", "末尾が / の URL が読めません");
  check(
    parse("https://github.com/toolbox/skills/tree/main/skills/pdf")?.path === "skills/pdf",
    "/tree/<ref>/<フォルダ> のフォルダが読めません",
  );
  check(parse("github.com/writer/plain-ja")?.owner === "writer", "https:// の無い github.com/… が読めません");
  check(parse("writer/plain-ja", "skills/plain-ja")?.path === "skills/plain-ja", "フォルダの指定が効きません");
  for (const bad of [
    "",
    "writer",
    "http://github.com/a/b",
    "https://gitlab.com/a/b",
    "https://github.com/../b",
    "../a/b",
    "a/b c",
    "-x/repo",
    "a/.git",
    "https://github.com/a/b/blob/main/SKILL.md",
  ]) {
    check(parse(bad) === null, `危ない・読めない出どころを通しています: ${JSON.stringify(bad)}`);
  }
  for (const folder of ["../etc", "skills/.hidden", "skills/../..", "-x"]) {
    check(parse("a/b", folder) === null, `危ないフォルダの指定を通しています: ${folder}`);
  }

  // ── 2. タグと frontmatter ─────────────────────────────────────
  check(
    tools.pickLatestTag(["v1.0.9", "v1.0.10", "v1.1.0-beta.1", "1.0.2", "latest"]) === "v1.0.10",
    "最新タグを数の順で選んでいません（文字の順や -beta を取っている）",
  );
  check(tools.pickLatestTag(["nightly", "v2-beta"]) === null, "semver でないタグを版として取っています");
  const front = tools.readFrontmatter(
    '---\nname: "yomi"\ndescription: >\n  一行目\n  二行目\nmetadata:\n  name: nested\n---\n本文',
  );
  check(front.name === "yomi" && front.description === "一行目 二行目", "frontmatter の引用符・複数行・入れ子を読み違えています");
  check(Object.keys(tools.readFrontmatter("本文だけ")).length === 0, "frontmatter の無い文を読み違えています");

  // ── 3. 入れる（直下と skills/<名前>/ に同じスキルを置く配り方） ──
  const outside = join(tmp, "outside");
  writeFiles(outside, { "x/SKILL.md": skillMd("x") });
  const yomi = makeRepo(
    "writer",
    "plain-ja",
    {
      "SKILL.md": skillMd("plain-ja"),
      "README.md": "# readme",
      "scripts/dev-only.py": "print('dev')",
      ".github/workflows/ci.yml": "on: push",
      ".claude-plugin/plugin.json": "{}",
      "skills/plain-ja/SKILL.md": skillMd("plain-ja"),
      "skills/plain-ja/VERSION": "v1.0.9",
      "skills/plain-ja/scripts/lint.py": "print('lint')",
      "skills/plain-ja/.hidden": "secret",
      "skills/plain-ja/link": { link: "/etc/hosts" },
    },
    ["v1.0.9"],
  );
  commit(yomi, { "skills/plain-ja/VERSION": "v1.0.10" }, ["v1.0.10"]);
  commit(yomi, { "skills/plain-ja/VERSION": "unreleased" });

  const homeA = newHome();
  const preview = run(homeA, "preview", "writer/plain-ja");
  const seen = preview.code === 0 ? JSON.parse(preview.out) : {};
  check(preview.code === 0, `preview が失敗しました: ${preview.last}`);
  check(
    seen.name === "plain-ja" && seen.version === "v1.0.10" && seen.path === "skills/plain-ja" && seen.description === "plain-ja の説明です。",
    `preview の中身が違います: ${preview.out}`,
  );
  check(Array.isArray(seen.conflicts) && seen.conflicts.length === 0, "何も無い HOME で preview が衝突を出しています");
  check(!existsSync(support(homeA)) && !existsSync(join(homeA, ".claude")), "preview が何かを書いています");

  const added = run(homeA, "add", "writer/plain-ja");
  check(added.code === 0 && added.out.includes("plain-ja（v1.0.10）を入れました"), `add が失敗しました: ${added.last}`);
  const installed = claudeSkill(homeA, "plain-ja");
  check(readFileSync(join(installed, "VERSION"), "utf8") === "v1.0.10", "最新タグではなく途中のコミットを入れています");
  check(existsSync(join(installed, "scripts", "lint.py")), "スキルのスクリプトが入っていません");
  check(!existsSync(join(installed, "README.md")) && !existsSync(join(installed, "scripts", "dev-only.py")),
    "直下（README や開発用のスクリプト）を入れています。skills/ の側を入れるはずです");
  check(!existsSync(join(installed, ".hidden")) && !existsSync(join(installed, "link")),
    "点で始まる物かリンクを持ち込んでいます");
  check(listDir(join(homeA, ".claude", "skills")).join(",") === "plain-ja", "スキルの置き場に作りかけのフォルダが残っています");
  check(listDir(join(support(homeA), "my-tools-staging")).length === 0, "組み立て場所に残り物があります");
  const itemA = recordOf(homeA).items[0] ?? {};
  check(
    itemA.name === "plain-ja" &&
      itemA.source === "https://github.com/writer/plain-ja" &&
      itemA.path === "skills/plain-ja" &&
      itemA.version === "v1.0.10" &&
      itemA.tag === "v1.0.10" &&
      /^[0-9a-f]{40}$/.test(itemA.commit ?? "") &&
      String(itemA.hash).startsWith("sha256:") &&
      JSON.stringify(itemA.agents) === '["claude-code"]',
    `控えの形が違います: ${JSON.stringify(itemA)}`,
  );
  const again = run(homeA, "add", "writer/plain-ja");
  check(again.code === 1 && again.last.includes("もう入っています"), "同じスキルを二重に入れています");

  // ── 5. 同じ名前を上書きしない ─────────────────────────────────
  const homeMine = newHome();
  writeFiles(claudeSkill(homeMine, "plain-ja"), { "SKILL.md": "mine" });
  const mineSeen = JSON.parse(run(homeMine, "preview", "writer/plain-ja").out || "{}");
  check(mineSeen.conflicts?.length === 1, "既にある同名のスキルを preview が衝突として出していません");
  const clash = run(homeMine, "add", "writer/plain-ja");
  check(clash.code === 1 && clash.last.includes("同じ名前のスキルが既にある"), `同名のスキルがあっても入れています: ${clash.last}`);
  check(readFileSync(join(claudeSkill(homeMine, "plain-ja"), "SKILL.md"), "utf8") === "mine", "本人のスキルを書き換えています");
  check(!existsSync(join(support(homeMine), "my-tools.json")), "入れていないのに控えを書いています");

  // ── 6. 版の確認 ───────────────────────────────────────────────
  const current = JSON.parse(run(homeA, "check").out || "[]")[0] ?? {};
  check(
    current.id === "my-skill:plain-ja" && current.current === "v1.0.10" && current.latest === "v1.0.10" &&
      current.status === "current" && current.modified === false,
    `最新なのに最新と出ていません: ${JSON.stringify(current)}`,
  );
  commit(yomi, { "skills/plain-ja/VERSION": "v1.0.11" }, ["v1.0.11"]);
  const behind = JSON.parse(run(homeA, "check").out || "[]")[0] ?? {};
  check(behind.status === "update" && behind.latest === "v1.0.11", `新しいタグがあるのに update と出ていません: ${JSON.stringify(behind)}`);

  // ── 7. 更新 ───────────────────────────────────────────────────
  const updated = run(homeA, "update");
  check(updated.code === 0 && updated.out.includes("plain-ja: v1.0.10 → v1.0.11") && updated.out.includes("1件を更新"),
    `更新の知らせが違います: ${updated.out}${updated.last}`);
  check(readFileSync(join(installed, "VERSION"), "utf8") === "v1.0.11", "更新で中身が入れ替わっていません");
  check(recordOf(homeA).items[0]?.version === "v1.0.11", "更新しても控えの版が古いままです");
  check(JSON.parse(run(homeA, "check").out || "[]")[0]?.status === "current", "更新のあとも update と出ています");

  const homeB = newHome();
  run(homeB, "add", "writer/plain-ja");
  commit(yomi, { "skills/plain-ja/VERSION": "v1.0.12" }, ["v1.0.12"]);
  appendFileSync(join(claudeSkill(homeB, "plain-ja"), "SKILL.md"), "\n本人が足した行\n");
  check(JSON.parse(run(homeB, "check").out || "[]")[0]?.modified === true, "手元で書き換えたことを check が出していません");
  const kept = run(homeB, "update");
  check(kept.code === 0 && kept.out.includes("手元で変えているので更新していません"), `書き換えた物の更新を止めていません: ${kept.out}`);
  check(readFileSync(join(claudeSkill(homeB, "plain-ja"), "VERSION"), "utf8") === "v1.0.11", "書き換えた物を入れ替えています");
  check(readFileSync(join(claudeSkill(homeB, "plain-ja"), "SKILL.md"), "utf8").includes("本人が足した行"), "本人が足した行が消えています");

  // ── 6. タグの無いリポジトリ ───────────────────────────────────
  const solo = makeRepo("solo", "notag", { "SKILL.md": skillMd("notag") });
  const homeC = newHome({ codex: true });
  const soloAdd = run(homeC, "add", "solo/notag");
  const soloItem = soloAdd.code === 0 ? recordOf(homeC).items[0] : {};
  check(soloAdd.code === 0 && /^[0-9a-f]{7}$/.test(soloItem.version ?? "") && soloItem.tag === null,
    `タグの無いリポジトリを先頭のコミットで入れていません: ${soloAdd.last}`);
  commit(solo, { "SKILL.md": skillMd("notag", "新しい説明です。") });
  const soloBehind = JSON.parse(run(homeC, "check").out || "[]")[0] ?? {};
  check(soloBehind.status === "update" && soloBehind.latest === git(solo, "rev-parse", "--short=7", "HEAD"),
    `タグの無いリポジトリの新しいコミットを update と出していません: ${JSON.stringify(soloBehind)}`);

  // ── 10. Codex ─────────────────────────────────────────────────
  check(existsSync(join(homeC, ".codex", "skills", "notag", "SKILL.md")) && JSON.stringify(soloItem.agents) === '["claude-code","codex"]',
    "Codex が入っている HOME で、Codex の置き場に入れていません");
  const soloUpdate = run(homeC, "update");
  check(soloUpdate.code === 0 && readFileSync(join(homeC, ".codex", "skills", "notag", "SKILL.md"), "utf8").includes("新しい説明です。"),
    "更新が Codex の置き場に届いていません");

  // ── 8. 危ない名前・外を指すフォルダ・複数のスキル ─────────────
  makeRepo("evil", "dots", { "SKILL.md": skillMd("../escape") });
  makeRepo("evil", "spaces", { "SKILL.md": skillMd("Has Space") });
  makeRepo("evil", "linkdir", { skills: { link: outside } });
  const homeD = newHome();
  for (const repo of ["evil/dots", "evil/spaces"]) {
    const bad = run(homeD, "add", repo);
    check(bad.code === 1 && bad.last.includes("使えない綴り"), `危ない名前のスキルを入れています: ${repo} ${bad.last}`);
  }
  const escaped = run(homeD, "add", "evil/linkdir");
  check(escaped.code === 1 && escaped.last.includes("リポジトリの外"), `リポジトリの外を指すフォルダから入れています: ${escaped.last}`);
  check(listDir(join(homeD, ".claude", "skills")).length === 0 && !existsSync(join(support(homeD), "my-tools.json")),
    "入れられなかったのに何かを書いています");

  makeRepo("toolbox", "skills", { "skills/pdf/SKILL.md": skillMd("pdf"), "skills/docx/SKILL.md": skillMd("docx") }, ["v1.0.0"]);
  const many = run(homeD, "add", "toolbox/skills");
  check(many.code === 1 && many.last.includes("スキルが複数あります") && many.last.includes("skills/pdf"),
    `スキルが複数あるのにフォルダを求めていません: ${many.last}`);
  const picked = run(homeD, "add", "toolbox/skills", "--path", "skills/pdf");
  check(picked.code === 0 && existsSync(join(claudeSkill(homeD, "pdf"), "SKILL.md")), `フォルダを指定して入れられません: ${picked.last}`);
  const byUrl = run(homeD, "add", "https://github.com/toolbox/skills/tree/main/skills/docx");
  check(byUrl.code === 0 && existsSync(join(claudeSkill(homeD, "docx"), "SKILL.md")), `/tree/… の URL で入れられません: ${byUrl.last}`);

  // ── 9. 外す ───────────────────────────────────────────────────
  appendFileSync(join(installed, "SKILL.md"), "\n本人が足した行\n");
  const refused = run(homeA, "remove", "plain-ja");
  check(refused.code === 1 && refused.last.includes("手元で変えている") && existsSync(installed), "書き換えた物を --force なしで消しています");
  const forced = run(homeA, "remove", "plain-ja", "--force");
  check(forced.code === 0 && !existsSync(installed) && recordOf(homeA).items.length === 0, "--force で外せていません");
  const plain = run(homeD, "remove", "pdf");
  check(plain.code === 0 && !existsSync(claudeSkill(homeD, "pdf")) && recordOf(homeD).items.every((item) => item.name !== "pdf"),
    "書き換えていない物を外せていません");
  check(run(homeD, "remove", "nothing").code === 1, "控えに無いスキルを外したと言っています");

  // ── 12. 確かめた中身を入れる・試用版だけなら断る ───────────────
  const pinRepo = makeRepo("review", "pinned", { "SKILL.md": skillMd("reviewed-name") }, ["v1.0.0"]);
  const pinHome = newHome();
  const pin = JSON.parse(run(pinHome, "preview", "review/pinned").out);
  const pinArgs = (seen) => ["--expect-commit", seen.commit, "--expect-name", seen.name];
  commit(pinRepo, { "SKILL.md": skillMd("unreviewed-name") }, ["v2.0.0"]);
  const different = run(pinHome, "add", pin.source, ...pinArgs(pin));
  check(different.code === 1 && different.last.includes("確かめた後"), "確かめた後に変わった名前・版を入れています");
  check(listDir(join(pinHome, ".claude", "skills")).length === 0 && !existsSync(join(support(pinHome), "my-tools.json")),
    "確かめた中身と違うのに、スキルか控えを書いています");
  const beforeMove = JSON.parse(run(pinHome, "preview", "review/pinned").out);
  commit(pinRepo, { "SKILL.md": skillMd("unreviewed-name", "同じタグでも中身を変えた") });
  git(pinRepo, "tag", "-f", "v2.0.0");
  const moved = run(pinHome, "add", beforeMove.source, ...pinArgs(beforeMove));
  check(moved.code === 1 && moved.last.includes("確かめた後"), "同じタグの指すコミットが変わったのに入れています");
  const reviewed = JSON.parse(run(pinHome, "preview", "review/pinned").out);
  const wrongName = run(pinHome, "add", reviewed.source, "--expect-commit", reviewed.commit, "--expect-name", "different-name");
  check(wrongName.code === 1 && wrongName.last.includes("確かめた後"), "確かめた名前の照合が効いていません");
  const exact = run(pinHome, "add", reviewed.source, ...pinArgs(reviewed));
  check(exact.code === 0 && recordOf(pinHome).items[0]?.commit === reviewed.commit,
    `確かめたコミットが変わっていないのに入れられません: ${exact.last}`);

  makeRepo("release", "beta-only", { "SKILL.md": skillMd("beta-only") }, ["v1.0.0-beta.1"]);
  const betaHome = newHome();
  for (const action of ["preview", "add"]) {
    const beta = run(betaHome, action, "release/beta-only");
    check(beta.code === 1 && beta.last.includes("正式版のタグがありません"), `試用版のタグしか無いのに ${action} が先頭を使っています`);
  }
  check(!existsSync(claudeSkill(betaHome, "beta-only")), "試用版だけのリポジトリから入れています");

  // ── 13. 手元の隠しファイルも守る ────────────────────────────
  const hiddenRepo = makeRepo("local", "hidden", { "SKILL.md": skillMd("hidden"), VERSION: "1" }, ["v1.0.0"]);
  const hiddenHome = newHome();
  run(hiddenHome, "add", "local/hidden");
  const hiddenNote = join(claudeSkill(hiddenHome, "hidden"), ".local-notes");
  writeFileSync(hiddenNote, "本人が残した非公開のメモ");
  commit(hiddenRepo, { VERSION: "2" }, ["v2.0.0"]);
  check(JSON.parse(run(hiddenHome, "check").out)[0]?.modified === true, "点で始まる手元の変更を見落としています");
  const hiddenUpdate = run(hiddenHome, "update");
  check(hiddenUpdate.code === 0 && hiddenUpdate.out.includes("手元で変えている") && existsSync(hiddenNote) &&
    readFileSync(join(claudeSkill(hiddenHome, "hidden"), "VERSION"), "utf8") === "1", "更新が手元の隠しファイルを消しています");
  check(run(hiddenHome, "remove", "hidden").code === 1 && existsSync(hiddenNote), "--force 無しで隠しファイルごと消しています");

  const linkRepo = makeRepo("local", "root-link", { "SKILL.md": skillMd("root-link"), VERSION: "1" }, ["v1.0.0"]);
  const linkHomes = ["live", "dangling"].map((kind) => {
    const linkHome = newHome();
    run(linkHome, "add", "local/root-link");
    const original = join(linkHome, "original-skill");
    renameSync(claudeSkill(linkHome, "root-link"), original);
    symlinkSync(kind === "live" ? original : join(linkHome, "missing-target"), claudeSkill(linkHome, "root-link"));
    return { linkHome, original, kind };
  });
  commit(linkRepo, { VERSION: "2" }, ["v2.0.0"]);
  for (const { linkHome, original, kind } of linkHomes) {
    check(JSON.parse(run(linkHome, "check").out)[0]?.modified === true, `${kind}: 根元をリンクに変えたことを見落としています`);
    const keptLink = run(linkHome, "update");
    check(keptLink.code === 0 && keptLink.out.includes("手元で変えている") && recordOf(linkHome).items[0].version === "v1.0.0",
      `${kind}: 手元のリンクを更新で差し替えています`);
    check(run(linkHome, "remove", "root-link").code === 1 && readFileSync(join(original, "VERSION"), "utf8") === "1",
      `${kind}: 本人が置いたリンクを --force 無しで消しています`);
  }

  // ── 14. 2つ目の置き場と控えの保存に失敗しても、全部元に戻す ──
  for (const action of ["add", "update", "remove"]) {
    for (const failure of ["second-target", "record"]) {
      const name = `${action}-${failure}`;
      const repo = makeRepo("atomic", name, { "SKILL.md": skillMd(name), VERSION: "1" }, ["v1.0.0"]);
      const atomicHome = newHome({ codex: true });
      const claude = claudeSkill(atomicHome, name);
      const codex = join(atomicHome, ".codex", "skills", name);
      const record = join(support(atomicHome), "my-tools.json");
      if (action !== "add") check(run(atomicHome, "add", `atomic/${name}`).code === 0, `${name}: 検査用の導入が失敗しました`);
      if (action === "update") commit(repo, { VERSION: "2" }, ["v2.0.0"]);
      const before = existsSync(record) ? readFileSync(record, "utf8") : null;
      const args = action === "add" ? [action, `atomic/${name}`] : action === "remove" ? [action, name] : [action];
      const fault = failure === "record" ? { to: record } : action === "remove" ? { from: codex } : { to: codex };
      const failed = runWithFailure(atomicHome, fault, ...args);
      check(failed.code === 1 && `${failed.out}${failed.err}`.includes("injected rename failure"), `${name}: 保存失敗を再現できていません`);
      check((existsSync(record) ? readFileSync(record, "utf8") : null) === before, `${name}: 失敗したのに控えが変わりました`);
      check([claude, codex].every((dir) => action === "add" ? !existsSync(dir) :
        existsSync(join(dir, "VERSION")) && readFileSync(join(dir, "VERSION"), "utf8") === "1"),
      `${name}: 失敗後、いずれかの置き場が元に戻っていません`);
      check(listDir(join(support(atomicHome), "my-tools-staging")).length === 0 &&
        !listDir(support(atomicHome)).some((entry) => entry.startsWith("my-tools.json.tmp-")), `${name}: 正常に戻せたのに途中の物が残っています`);
      const retry = run(atomicHome, ...args);
      check(retry.code === 0, `${name}: 保存失敗を直しても再試行できません: ${retry.out}${retry.last}`);
      if (action === "remove") {
        check(!existsSync(claude) && !existsSync(codex) && recordOf(atomicHome).items.length === 0, `${name}: 再試行しても外せません`);
      } else {
        const expected = action === "update" ? "2" : "1";
        check([claude, codex].every((dir) => readFileSync(join(dir, "VERSION"), "utf8") === expected) &&
          recordOf(atomicHome).items[0]?.version === `v${expected}.0.0`, `${name}: 再試行後の両方の中身と控えが揃いません`);
      }
    }
  }

  // ── 11. 壊れた控え・重ねて走らせない ─────────────────────────
  const homeE = newHome();
  mkdirSync(support(homeE), { recursive: true });
  writeFileSync(join(support(homeE), "my-tools.json"), "{ 壊れた");
  const broken = run(homeE, "add", "solo/notag");
  check(broken.code === 1 && broken.last.includes("控えが壊れています") &&
    readFileSync(join(support(homeE), "my-tools.json"), "utf8") === "{ 壊れた", "壊れた控えを書き直しています");

  const homeF = newHome();
  mkdirSync(support(homeF), { recursive: true });
  const lock = join(support(homeF), "my-tools.lock");
  writeFileSync(lock, "");
  const busy = run(homeF, "add", "solo/notag");
  check(busy.code === 1 && busy.last.includes("ほかの追加・更新が走っています"), "錠があるのに走っています");
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000);
  utimesSync(lock, hourAgo, hourAgo);
  const stale = run(homeF, "add", "solo/notag");
  check(stale.code === 0 && !existsSync(lock), `古い錠で止まったままです: ${stale.last}`);

  // 逐次の検査では、読んでから書く錠（原子的でない錠）も通ってしまう。同時に5本走らせる。
  const homeG = newHome();
  const racers = await Promise.all(Array.from({ length: 5 }, () => runAsync(homeG, "add", "solo/notag")));
  const winners = racers.filter((racer) => racer.code === 0).length;
  check(winners === 1, `同時に5本走らせたら ${winners} 本が入れました（1本だけのはず）`);
  check(racers.every((racer) => racer.code === 0 || /ほかの追加・更新が走っています|もう入っています/.test(racer.last)),
    `同時に走らせたときの断り方が違います: ${racers.map((racer) => racer.last).join(" / ")}`);
  check(recordOf(homeG).items.length === 1 && !existsSync(join(support(homeG), "my-tools.lock")),
    "同時に走らせたあと、控えが重複したか錠が残っています");
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

if (failures > 0) {
  process.stderr.write(`${failures} 件、自分で選んだスキルの入れ口が期待どおりに動いていません\n`);
  process.exit(1);
}
process.stdout.write(
  `出どころの読み方・正式版と確かめたコミットだけを入れる・skills/ の側を入れる・点とリンクを持ち込まない・preview は書かない・同名を上書きしない・版の確認（タグ／先頭）・隠しファイルを含む手元の変更を守る・危ない名前と外を指すフォルダを断る・複数の置き場と控えを失敗時に元に戻す・Codex の置き場・壊れた控えと錠（${checks} 項目）\n`,
);
