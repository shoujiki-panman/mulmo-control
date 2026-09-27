// 画面ガイドの説明文を検査する（Issue #224）。
//
// check.sh から `node tests/guide-text-test.mjs` で呼ぶ。
//
// 1. **説明は全部2段**（何をするか・どんな時に使うか）。1段だけだと「何をするか」は
//    分かっても、それを**いつ押すのか**が分からない、と言われた。
// 2. **吹き出しをはみ出させない長さ。** 1段 50 字まで（幅 300px で3行ほど）。
// 3. **当てる印が、いま入っている MulmoTerminal に実在する。** 上流が印を変えると
//    説明は黙って出なくなるだけなので、配布物（画面の JS とサーバー）を読んで突き合わせる。
//    MulmoTerminal が入っていない Mac（CI など）では、この段だけ飛ばしてそう書く。
//
// 読み方: ガイドはブラウザで動く1本の即時関数。document の無い箱で走らせると、
// 表だけを globalThis.mulmoGuideTables に置いて帰る（ガイド側にその口がある）。

import vm from "node:vm";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const GUIDE = fileURLToPath(new URL("../guide/mulmoterminal-guide.js", import.meta.url));
const MAX_CHARS = 50;

let failures = 0;
const fail = (label) => {
  failures += 1;
  process.stderr.write(`  ✗ ${label}\n`);
};

// ── 表を取り出す ─────────────────────────────────────────────
const box = {};
vm.createContext(box);
vm.runInContext(readFileSync(GUIDE, "utf8"), box, { filename: GUIDE });
const tables = box.mulmoGuideTables;
if (tables === undefined) {
  process.stderr.write("  ✗ ガイドが表を出す口（mulmoGuideTables）を持っていません\n");
  process.exit(1);
}

/** [種類, 印, 説明] の並び。 */
const entries = [
  ...Object.entries(tables.BY_TESTID).map(([mark, text]) => ["testid", mark, text]),
  // Skill メニュー（Issue #226）。同梱スキルの日本語と、メニューを開くボタン。
  ...Object.entries(tables.BY_SKILL ?? {}).map(([mark, text]) => ["skill", mark, text]),
  ["skill-button", tables.SKILL_MENU_TITLE, tables.SKILL_BUTTON],
  ...Object.entries(tables.BY_ARIA).map(([mark, text]) => ["aria", mark, text]),
  ...tables.BY_ARIA_PREFIX.map(([mark, text]) => ["prefix", mark, text]),
];
if (entries.length === 0) fail("説明が1つもありません");

// ── 1・2. 2段であること・長さ ────────────────────────────────
const length = (text) => [...text].length;
for (const [kind, mark, text] of entries) {
  const where = `${kind} "${mark}"`;
  if (!Array.isArray(text) || text.length !== 2) {
    fail(`${where}: 説明が「何をするか・どんな時に使うか」の2段になっていません`);
    continue;
  }
  const [what, when] = text;
  if (typeof what !== "string" || what.trim() === "") fail(`${where}: 「何をするか」が空です`);
  if (typeof when !== "string" || when.trim() === "") fail(`${where}: 「どんな時に使うか」が空です`);
  if (what === when) fail(`${where}: 2段が同じ文です`);
  if (typeof what === "string" && length(what) > MAX_CHARS) fail(`${where}: 「何をするか」が ${length(what)} 字（上限 ${MAX_CHARS}）`);
  if (typeof when === "string" && length(when) > MAX_CHARS) fail(`${where}: 「どんな時に使うか」が ${length(when)} 字（上限 ${MAX_CHARS}）`);
}

// ── Skill メニュー: 本人やプロジェクトのスキルの出し方（Issue #226）──
//
// 同梱スキルは表の日本語。それ以外は、その場の説明を1〜2文に畳んで出す。
// 英語の説明は中継の訳があればそれ、無ければ**原文のまま**（画面の側で訳を捏造しない）。
// スキルは架空のもの。
{
  const { skillText, foldDescription, MAX_FOLD, BY_SKILL } = tables;
  if (typeof skillText !== "function" || typeof foldDescription !== "function") {
    fail("ガイドが Skill メニューの説明を組む口（skillText / foldDescription）を持っていません");
  } else {
    const bundled = Object.keys(BY_SKILL)[0];
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    if (bundled === undefined || !same(skillText(bundled, "Anything in English.", {}), BY_SKILL[bundled])) {
      fail("同梱スキルに、表の日本語が出ません");
    }
    const own = "架空のメモを日付ごとに整理する。週の終わりにまとめる。「メモ整理」で使う。";
    if (!same(skillText("example-notes", own, {}), ["架空のメモを日付ごとに整理する。週の終わりにまとめる。", ""])) {
      fail(`本人のスキルの説明が1〜2文に畳まれていません（${JSON.stringify(skillText("example-notes", own, {}))}）`);
    }
    const english = "Draft the example widget report. Keep it ready by Friday. Use it weekly.";
    if (!same(skillText("example-report", english, {}), ["Draft the example widget report. Keep it ready by Friday.", ""])) {
      fail("訳の無い英語の説明が、原文のまま出ていません");
    }
    if (!same(skillText("example-report", english, { [english]: "架空の報告を下書きします。" }), ["架空の報告を下書きします。", ""])) {
      fail("中継の訳があるのに、英語の説明が出ています");
    }
    if (skillText("example-empty", "", {}) !== null) fail("説明の無いスキルに吹き出しを出しています");
    if (foldDescription("Reads config.json and v1.2 files only.") !== "Reads config.json and v1.2 files only.") {
      fail("ファイル名や版の点で文を切っています");
    }
    if ([...foldDescription("あ".repeat(MAX_FOLD * 2))].length > MAX_FOLD) fail(`畳んだ説明が ${MAX_FOLD} 字を超えています`);
  }
}

// ── 3. 印が配布物に実在すること ──────────────────────────────
function findMulmoTerminal() {
  const candidates = [
    process.env.MULMOTERMINAL_DIR,
    join(homedir(), ".local/share/mulmoterminal/node_modules/mulmoterminal"),
  ].filter(Boolean);
  return candidates.find((dir) => existsSync(join(dir, "dist")) && existsSync(join(dir, "package.json")));
}

/** 画面の JS（dist）とサーバー（server）の中身をつないだもの。印はこのどちらかに書いてある。 */
function readShipped(dir) {
  const parts = [];
  const walk = (path) => {
    for (const name of readdirSync(path)) {
      if (name === "node_modules") continue;
      const child = join(path, name);
      if (statSync(child).isDirectory()) walk(child);
      else if (/\.(m?js|ts|html)$/.test(name)) parts.push(readFileSync(child, "utf8"));
    }
  };
  for (const sub of ["dist", "server"]) if (existsSync(join(dir, sub))) walk(join(dir, sub));
  return parts.join("\n");
}

/** 文字列として書かれているか。引用符（" ' `）で閉じた形で探す。頭で当てるものは閉じない。 */
function shipped(code, kind, mark) {
  if (kind === "prefix") return ['"', "'", "`"].some((q) => code.includes(q + mark));
  return ['"', "'", "`"].some((q) => code.includes(q + mark + q));
}

const mtDir = findMulmoTerminal();
let markNote;
if (mtDir === undefined) {
  markNote = "MulmoTerminal が入っていないので、印の実在は見ていません";
} else {
  const version = JSON.parse(readFileSync(join(mtDir, "package.json"), "utf8")).version;
  const code = readShipped(mtDir);
  const missing = entries.filter(([kind, mark]) => kind !== "skill" && !shipped(code, kind, mark));
  for (const [kind, mark] of missing) {
    fail(`${kind} "${mark}" が MulmoTerminal ${version} の配布物にありません。上流で消えたなら説明も消してください`);
  }
  // 同梱スキル: 表の名前が配布物に実在し、配布物の同梱スキルが全部表にある（Issue #226）。
  // 上流が1本足した日に、そのスキルだけ英語のまま（中継は同梱を訳さない）になるのを拾う。
  const skillsDir = join(mtDir, "server", "skills");
  const shippedSkills = existsSync(skillsDir)
    ? readdirSync(skillsDir).filter((name) => existsSync(join(skillsDir, name, "SKILL.md")))
    : [];
  for (const name of Object.keys(tables.BY_SKILL)) {
    if (!shippedSkills.includes(name)) fail(`同梱スキル "${name}" が MulmoTerminal ${version} の配布物にありません`);
  }
  const { BUNDLED_PREFIX } = await import(new URL("../scripts/mulmoterminal-guide-skill-ja.mjs", import.meta.url));
  for (const name of shippedSkills) {
    if (!Object.hasOwn(tables.BY_SKILL, name)) fail(`同梱スキル "${name}" の日本語の説明がガイドにありません`);
    if (!name.startsWith(BUNDLED_PREFIX)) fail(`同梱スキル "${name}" が "${BUNDLED_PREFIX}" で始まらず、中継が訳させてしまいます`);
  }
  // Skill メニューの形: 項目が説明を title に持つ。ガイドはそこを読む。
  if (!/role:`menuitem`,title:\w+\.description/.test(code)) {
    fail(`MulmoTerminal ${version} の Skill メニューの項目が、説明を title に持っていません`);
  }
  markNote = `印 ${entries.length} 個が MulmoTerminal ${version} の配布物に実在する（同梱スキル ${shippedSkills.length} 本すべてに日本語あり）`;
}

if (failures > 0) process.exit(1);
process.stdout.write(`画面ガイドの説明 ${entries.length} 件が全部2段・1段 ${MAX_CHARS} 字以内・${markNote}\n`);
