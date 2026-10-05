// 自分で選んだスキル（GitHub）を入れて、版を確かめ、入れ替える入れ口（Issue #229）。
//
//   node mulmo-my-tools.mjs preview <出どころ> [--path <フォルダ>]   入れる前に、名前・説明・取る版を JSON で出す
//   node mulmo-my-tools.mjs add <出どころ> [--path <フォルダ>] [--expect-commit <SHA> --expect-name <名前>]
//                                                                確かめた中身と照合して、入れて控える
//   node mulmo-my-tools.mjs check                                  控えた各スキルの版を JSON で出す
//   node mulmo-my-tools.mjs update                                 新しい版があるものを入れ替える
//   node mulmo-my-tools.mjs remove <名前> [--force]                 入れたフォルダと控えを消す
//   node mulmo-my-tools.mjs list                                   控えを JSON で出す
//
// 出どころは `owner/repo` か `https://github.com/owner/repo`（`/tree/<ref>/<フォルダ>` 付きも可）。
// v1 は GitHub の HTTPS だけ。失敗したときは、理由を標準エラーの最後の行に書いて 1 で終わる
// （画面はその行を出す）。
//
// 追加ツール（familyPackages）は作者が決め打ちで並べていて、npm に無い物は入れられなかった。
// 使いたい物は人ごとに違うので、利用者が自分で足し、足した物も session-relay と同じく、
// 版の確認と `まとめて更新` の対象にする。
//
// ── 守ること ─────────────────────────────────────────────────
//
// 1. **リリースされた版を取る。** タグがあるリポジトリは、いちばん新しい semver のタグを取る。
//    `-beta` などの付いた版と、タグの後に積まれた途中のコミットは配らない。タグが無い
//    リポジトリだけ、既定ブランチの先頭を取る。
// 2. **外の物を持ち込まない。** 点で始まる物（`.git` `.github` など）とリンクはコピーしない。
//    リンクはリポジトリの外（`~/.ssh` など）を指せるため。スキルのフォルダがリポジトリの
//    外に解決される形（`skills` 自体がリンクなど）も断る。
// 3. **人の物を上書きしない。** 同じ名前のスキルが既にあれば、入れずに止まる。更新も、
//    控えたハッシュと今の中身が同じとき（手元で書き換えていないとき）だけ入れ替える。
// 4. **名前をそのままパスにしない。** frontmatter の `name` は Claude Code のスキル名の綴り
//    （小文字・数字・ハイフン、64字まで）だけを通す。控えから読んだ名前も同じ検査を通す。
//
// git は MULMO_GIT、GitHub の代わりに見る場所は MULMO_MY_TOOLS_GITHUB で差し替えられる
// （検査で、使い捨ての git リポジトリを GitHub に見立てるため）。

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  closeSync,
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, sep } from "node:path";
import { pathToFileURL } from "node:url";

const GITHUB = "https://github.com";
export const NAME_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$/;
// owner / repo / フォルダの1段。点で始まる物（`.` `..` `.git`）と、git に渡したときに
// オプションと読まれうる `-` で始まる物を通さない。
const SEGMENT_PATTERN = /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/;
const STABLE_TAG = /^v?(\d+)\.(\d+)\.(\d+)$/;
const LOCK_STALE_MS = 10 * 60 * 1000;
const GIT_TIMEOUT_MS = 60 * 1000;
const CLONE_TIMEOUT_MS = 3 * 60 * 1000;

// ── 置き場所 ─────────────────────────────────────────────────

const home = () => process.env.HOME ?? "";
const supportDir = () => join(home(), "Library", "Application Support", "Mulmo Control");
export const recordPath = () => join(supportDir(), "my-tools.json");

// Codex のスキルの置き場は実機で確かめる（#229）。入っていない人には置かない。
const AGENT_SKILL_ROOTS = {
  "claude-code": () => join(home(), ".claude", "skills"),
  codex: () => join(home(), ".codex", "skills"),
};

function detectAgents() {
  const agents = ["claude-code"];
  if (existsSync(join(home(), ".codex"))) agents.push("codex");
  return agents;
}

function skillDir(agent, name) {
  const root = AGENT_SKILL_ROOTS[agent];
  if (!root) throw new Error(`知らない置き場です: ${agent}`);
  return join(root(), mustName(name));
}

// ── 出どころ ─────────────────────────────────────────────────

/** `owner/repo`・GitHub の URL を読む。読めない・危ない綴りなら null。 */
export function parseSource(input, folder = "") {
  let text = String(input ?? "").trim();
  if (text.startsWith("github.com/")) text = `https://${text}`;
  const url = /^https:\/\/github\.com\/([^/]+)\/([^/]+?)(?:\.git)?(?:\/tree\/[^/]+(\/.*)?)?\/?$/.exec(text);
  const short = /^([^/:\s]+)\/([^/:\s]+?)(?:\.git)?$/.exec(text);
  const match = url ?? short;
  if (!match) return null;
  const [, owner, repo] = match;
  const path = trimSlashes(folder ? String(folder) : (url?.[3] ?? ""));
  if (!SEGMENT_PATTERN.test(owner) || !SEGMENT_PATTERN.test(repo)) return null;
  if (path && !path.split("/").every((segment) => SEGMENT_PATTERN.test(segment))) return null;
  return { owner, repo, path, url: `${GITHUB}/${owner}/${repo}` };
}

const trimSlashes = (text) => text.trim().replace(/^\/+|\/+$/g, "");

function mustParse(input, folder) {
  const source = parseSource(input, folder);
  if (!source) throw new Error(`出どころが読めません: ${input}（owner/repo か https://github.com/owner/repo）`);
  return source;
}

function remoteUrl(source) {
  const base = process.env.MULMO_MY_TOOLS_GITHUB;
  return base ? `${base}/${source.owner}/${source.repo}` : `${source.url}.git`;
}

// ── git ─────────────────────────────────────────────────────

function git(args, timeout = GIT_TIMEOUT_MS) {
  try {
    return execFileSync(process.env.MULMO_GIT || "git", args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout,
      // 公開リポジトリだけを扱う。認証を尋ねて止まったままにならないよう、尋ねさせない。
      env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
    }).trim();
  } catch (error) {
    throw new Error(gitFailure(error));
  }
}

function gitFailure(error) {
  if (error.code === "ENOENT") return "git が見つかりません（Xcode のコマンドラインツールが要ります）";
  if (error.signal === "SIGTERM") return "git が時間内に終わりませんでした";
  const line = String(error.stderr ?? "").trim().split("\n").pop();
  return line ? `git が失敗しました: ${line}` : "git が失敗しました";
}

/** semver のタグのうち、いちばん新しいもの。`-beta` などの付いたタグは数えない。 */
export function pickLatestTag(tags) {
  let best = null;
  for (const tag of tags) {
    const match = STABLE_TAG.exec(tag);
    if (!match) continue;
    const key = match.slice(1, 4).map(Number);
    if (!best || compareVersions(key, best.key) > 0) best = { tag, key };
  }
  return best?.tag ?? null;
}

const compareVersions = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

/** 正式版のタグを取る。タグ自体が無いときだけ既定ブランチの先頭に落ちる。 */
export function remoteVersion(source) {
  const url = remoteUrl(source);
  const tags = git(["ls-remote", "--tags", "--refs", url])
    .split("\n")
    .map((line) => line.split("\t")[1] ?? "")
    .filter((ref) => ref.startsWith("refs/tags/"))
    .map((ref) => ref.slice("refs/tags/".length));
  const tag = pickLatestTag(tags);
  if (tag) return { tag, label: tag };
  if (tags.length) throw new Error("正式版のタグがありません（試用版や途中のコミットは入れません）");
  const head = git(["ls-remote", url, "HEAD"]).split(/\s+/)[0] ?? "";
  if (!/^[0-9a-f]{40}$/.test(head)) throw new Error("リポジトリの版を読めませんでした");
  return { tag: null, label: head.slice(0, 7) };
}

function fetchSource(source, version, workDir) {
  const dir = join(workDir, "repo");
  const args = ["clone", "--quiet", "--depth", "1"];
  if (version.tag) args.push("--branch", version.tag);
  args.push("--", remoteUrl(source), dir);
  git(args, CLONE_TIMEOUT_MS);
  return { dir, commit: git(["-C", dir, "rev-parse", "HEAD"]) };
}

// タグが無いリポジトリは、版の名前を実際に取れたコミットで決める（ls-remote の後に
// 先頭が動いても、控えと中身がずれないように）。
const versionLabel = (version, commit) => version.tag ?? commit.slice(0, 7);

// ── SKILL.md ────────────────────────────────────────────────

/** frontmatter の1段目の `key: value` を読む。`>` / `|` の複数行と引用符に対応する。 */
export function readFrontmatter(text) {
  const block = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(String(text));
  if (!block) return {};
  const lines = block[1].split(/\r?\n/);
  const fields = {};
  for (let i = 0; i < lines.length; i += 1) {
    const pair = /^([A-Za-z][\w-]*):[ \t]*(.*)$/.exec(lines[i]);
    if (!pair) continue;
    let value = pair[2].trim();
    if (/^[>|][-+]?$/.test(value)) {
      const parts = [];
      while (i + 1 < lines.length && (/^[ \t]+\S/.test(lines[i + 1]) || lines[i + 1].trim() === "")) {
        i += 1;
        parts.push(lines[i].trim());
      }
      value = parts.filter(Boolean).join(value.startsWith(">") ? " " : "\n");
    }
    fields[pair[1]] = unquote(value);
  }
  return fields;
}

function unquote(value) {
  const match = /^(["'])([\s\S]*)\1$/.exec(value);
  return match ? match[2] : value;
}

function mustName(name) {
  if (!NAME_PATTERN.test(String(name ?? ""))) {
    // 名前は他人のリポジトリの文字列。改行などで画面の最後の行を乗っ取らせない。
    const shown = JSON.stringify(String(name ?? "")).slice(0, 80);
    throw new Error(`スキルの名前が使えない綴りです: ${shown}（小文字・数字・ハイフン、64字まで）`);
  }
  return name;
}

function hasSkillMd(dir) {
  try {
    return lstatSync(join(dir, "SKILL.md")).isFile();
  } catch {
    return false;
  }
}

function childSkillDirs(dir) {
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
    .map((entry) => join(dir, entry.name))
    .filter(hasSkillMd);
}

const skillMeta = (dir) => readFrontmatter(readFileSync(join(dir, "SKILL.md"), "utf8"));
const relativePath = (root, dir) => relative(root, dir).split(sep).join("/");

/**
 * リポジトリの中のスキルのフォルダを決める。
 *
 * フォルダの指定があればそれ。無ければ直下の SKILL.md。直下と `skills/<名前>/` に同じ
 * スキルを置く配り方（yomiyasu など）では、直下に README や開発用のスクリプトも並ぶので、
 * 名前が同じなら `skills/` の側を取る。直下に無ければ1段下を探し、1つに決まらなければ
 * フォルダを指定してもらう。
 */
export function findSkillDir(root, path = "") {
  if (path) return insideRepo(root, join(root, ...path.split("/")));
  const nested = childSkillDirs(join(root, "skills"));
  if (hasSkillMd(root)) {
    const name = skillMeta(root).name;
    const same = nested.filter((dir) => skillMeta(dir).name === name);
    return insideRepo(root, same.length === 1 ? same[0] : root);
  }
  const candidates = [...new Set([...nested, ...childSkillDirs(root)])];
  if (candidates.length === 1) return insideRepo(root, candidates[0]);
  if (candidates.length === 0) throw new Error("SKILL.md が見つかりません");
  const names = candidates.map((dir) => relativePath(root, dir)).join("、");
  throw new Error(`スキルが複数あります（${names}）。フォルダを指定してください`);
}

function insideRepo(root, dir) {
  if (!hasSkillMd(dir)) throw new Error(`${relativePath(root, dir) || "直下"} に SKILL.md がありません`);
  const real = realpathSync(dir);
  const top = realpathSync(root);
  if (real !== top && !real.startsWith(`${top}${sep}`)) throw new Error("スキルのフォルダがリポジトリの外を指しています");
  return { dir, path: relativePath(root, dir) };
}

// ── 中身 ─────────────────────────────────────────────────────

/** 点で始まる物とリンクを除いて写す。リンクはリポジトリの外を指せる。 */
function copyTree(from, to) {
  mkdirSync(to, { recursive: true });
  for (const entry of readdirSync(from, { withFileTypes: true })) {
    if (entry.name.startsWith(".")) continue;
    const source = join(from, entry.name);
    const target = join(to, entry.name);
    if (entry.isDirectory()) copyTree(source, target);
    else if (entry.isFile()) copyFileSync(source, target);
  }
}

/** 手元の隠しファイルも含めたハッシュ。コピー元を絞る規則とは分けて、利用者の変更を守る。 */
export function hashTree(dir) {
  const hash = createHash("sha256");
  const walk = (current, prefix) => {
    for (const name of readdirSync(current).sort()) {
      const path = join(current, name);
      const rel = prefix ? `${prefix}/${name}` : name;
      const stat = lstatSync(path);
      if (stat.isDirectory()) walk(path, rel);
      else if (stat.isFile()) hash.update(`f:${rel}\0`).update(readFileSync(path)).update("\0");
      else hash.update(`o:${rel}\0`);
    }
  };
  walk(dir, "");
  return `sha256:${hash.digest("hex")}`;
}

/**
 * 全ての置き場と控えを1組で変える。前の中身は控えの保存が終わるまで残す。
 * 途中で失敗したら、先に変えた置き場も戻す。復旧にも失敗した場合は控えを消さず、
 * 保存先を知らせる。from が null のときは取り外し。
 * 作りかけと退避先はスキルの置き場に置かない（同名のスキルを二重に読ませない）。
 */
function changeSkills(from, targets, save) {
  const staging = join(supportDir(), "my-tools-staging");
  mkdirSync(staging, { recursive: true });
  const work = mkdtempSync(join(staging, "transaction-"));
  const changes = targets.map((target, index) => ({
    target,
    fresh: join(work, `new-${index}`),
    old: join(work, `old-${index}`),
    backedUp: false,
    installed: false,
  }));
  let retainBackup = false;
  try {
    // 全て組み立ててから置き換え始める。コピー失敗では既存の中身に触れない。
    if (from) {
      for (const change of changes) {
        mkdirSync(dirname(change.target), { recursive: true });
        copyTree(from, change.fresh);
      }
    }
    try {
      for (const change of changes) {
        if (pathExists(change.target)) {
          renameSync(change.target, change.old);
          change.backedUp = true;
        }
        if (from) {
          renameSync(change.fresh, change.target);
          change.installed = true;
        }
      }
      return save();
    } catch (error) {
      const failures = [];
      for (const change of [...changes].reverse()) {
        try {
          if (change.installed) rmSync(change.target, { recursive: true, force: true });
          if (change.backedUp) renameSync(change.old, change.target);
        } catch (restoreError) {
          failures.push(restoreError.message);
        }
      }
      if (failures.length) {
        retainBackup = true;
        throw new Error(`${error.message}。元に戻せなかった中身は ${work} に残しています: ${failures.join("、")}`);
      }
      throw error;
    }
  } finally {
    if (!retainBackup) {
      // 保存後の片付けの失敗を「更新失敗」としない。控えと中身は既に揃っている。
      try { rmSync(work, { recursive: true, force: true }); } catch { /* 次の検査・手動片付けに残す */ }
    }
  }
}

function pathExists(path) {
  try { lstatSync(path); return true; } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

// ── 控え ─────────────────────────────────────────────────────

export function readRecord() {
  let raw;
  try {
    raw = readFileSync(recordPath(), "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return { version: 1, items: [] };
    throw error;
  }
  // 読めない控えを空とみなして書き直すと、入れた物の控えが黙って消える。止まる。
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error(`控えが壊れています: ${recordPath()}`);
  }
  if (!Array.isArray(data?.items)) throw new Error(`控えの形が違います: ${recordPath()}`);
  return data;
}

function writeRecord(record) {
  const path = recordPath();
  mkdirSync(dirname(path), { recursive: true });
  const temporary = `${path}.tmp-${process.pid}`;
  try {
    writeFileSync(temporary, `${JSON.stringify(record, null, 2)}\n`);
    renameSync(temporary, path);
  } finally {
    try { rmSync(temporary, { force: true }); } catch { /* 元の保存エラーを保つ */ }
  }
}

/** 追加・更新・取り外しは1本ずつ（画面の連打と、巡回の更新が重ならないように）。 */
function withLock(action) {
  mkdirSync(supportDir(), { recursive: true });
  const lock = join(supportDir(), "my-tools.lock");
  try {
    if (Date.now() - statSync(lock).mtimeMs > LOCK_STALE_MS) rmSync(lock, { force: true });
  } catch {
    // 錠が無い（いつもの形）
  }
  let fd;
  try {
    fd = openSync(lock, "wx");
  } catch {
    throw new Error("ほかの追加・更新が走っています。終わってからもう一度押してください");
  }
  try {
    return action();
  } finally {
    closeSync(fd);
    rmSync(lock, { force: true });
  }
}

function withWorkDir(action) {
  const work = mkdtempSync(join(tmpdir(), "mulmo-my-tools-"));
  try {
    return action(work);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

// ── 操作 ─────────────────────────────────────────────────────

function inspect(source, work) {
  const version = remoteVersion(source);
  const { dir, commit } = fetchSource(source, version, work);
  const found = findSkillDir(dir, source.path);
  const meta = skillMeta(found.dir);
  return {
    found,
    commit,
    name: mustName(meta.name),
    description: meta.description ?? "",
    tag: version.tag,
    version: versionLabel(version, commit),
  };
}

/** 入れる前に見せるもの。何も書かない。 */
export function preview(input, folder = "") {
  const source = mustParse(input, folder);
  return withWorkDir((work) => {
    const seen = inspect(source, work);
    const targets = detectAgents().map((agent) => skillDir(agent, seen.name));
    return {
      name: seen.name,
      description: seen.description,
      source: source.url,
      path: seen.found.path,
      version: seen.version,
      commit: seen.commit,
      targets,
      conflicts: targets.filter(pathExists),
    };
  });
}

export function add(input, folder = "", { expectedCommit, expectedName } = {}) {
  const source = mustParse(input, folder);
  return withLock(() => {
    const record = readRecord();
    return withWorkDir((work) => {
      const seen = inspect(source, work);
      if ((expectedCommit !== undefined && seen.commit !== expectedCommit) ||
          (expectedName !== undefined && seen.name !== expectedName)) {
        throw new Error("確かめた後にスキルの中身が変わりました。もう一度「確かめる」を押してください");
      }
      if (record.items.some((item) => item.name === seen.name)) throw new Error(`「${seen.name}」はもう入っています`);
      const agents = detectAgents();
      const targets = agents.map((agent) => skillDir(agent, seen.name));
      const taken = targets.filter(pathExists);
      if (taken.length) throw new Error(`同じ名前のスキルが既にあるので入れていません: ${taken.join("、")}`);
      return changeSkills(seen.found.dir, targets, () => {
        const now = new Date().toISOString();
        const item = {
          kind: "skill",
          name: seen.name,
          source: source.url,
          path: seen.found.path,
          version: seen.version,
          tag: seen.tag,
          commit: seen.commit,
          hash: hashTree(targets[0]),
          agents,
          installedAt: now,
          updatedAt: now,
        };
        writeRecord({ ...record, items: [...record.items, item] });
        return item;
      });
    });
  });
}

function storedSource(item) {
  const source = parseSource(item.source, item.path);
  if (!source) throw new Error(`控えの出どころが読めません: ${item.source}`);
  return source;
}

const changedLocally = (item) =>
  item.agents.some((agent) => {
    const dir = skillDir(agent, item.name);
    // リンクへの置き換えも本人の変更。existsSync は切れたリンクを「無い」と読むので
    // lstat で根元を確かめ、リンク先をハッシュして同じ物だと誤読しない。
    return pathExists(dir) && (!lstatSync(dir).isDirectory() || hashTree(dir) !== item.hash);
  });

/**
 * 各スキルの版。mulmo-check-updates が `mulmo-updates.json` の項目として並べられるよう、
 * 同じ形（id / name / current / latest / status）で返す。
 */
export function check() {
  return readRecord().items.map((item) => {
    const present = hasSkillMd(skillDir(item.agents[0], item.name));
    let latest = "unknown";
    try {
      latest = remoteVersion(storedSource(item)).label;
    } catch {
      // 版が読めないときは unknown のまま（画面は「未確認」）
    }
    const current = present ? item.version : "unknown";
    const status = !present ? "missing" : latest === "unknown" ? "unknown" : current === latest ? "current" : "update";
    return { id: `my-skill:${item.name}`, name: item.name, current, latest, status, modified: changedLocally(item) };
  });
}

function updateOne(item, record) {
  const source = storedSource(item);
  const version = remoteVersion(source);
  if (version.label === item.version) return { name: item.name, outcome: "current" };
  if (changedLocally(item)) return { name: item.name, outcome: "kept", text: `${item.name}: 手元で変えているので更新していません` };
  return withWorkDir((work) => {
    const { dir, commit } = fetchSource(source, version, work);
    const found = insideRepo(dir, item.path ? join(dir, ...item.path.split("/")) : dir);
    const name = skillMeta(found.dir).name;
    if (name !== item.name) throw new Error(`名前が ${name} に変わったので入れ替えていません`);
    const targets = item.agents.map((agent) => skillDir(agent, item.name));
    return changeSkills(found.dir, targets, () => {
      const updated = {
        ...item,
        version: versionLabel(version, commit),
        tag: version.tag,
        commit,
        hash: hashTree(targets[0]),
        updatedAt: new Date().toISOString(),
      };
      const next = { ...record, items: record.items.map((entry) => entry === item ? updated : entry) };
      writeRecord(next);
      record.items = next.items;
      return { name: item.name, outcome: "updated", text: `${item.name}: ${item.version} → ${updated.version}` };
    });
  });
}

/** 新しい版があるものを入れ替える。1つが失敗しても残りは続ける。 */
export function update() {
  return withLock(() => {
    const record = readRecord();
    const results = record.items.map((item) => {
      try {
        return updateOne(item, record);
      } catch (error) {
        return { name: item.name, outcome: "failed", text: `${item.name}: ${error.message}` };
      }
    });
    return results;
  });
}

export function remove(name, { force = false } = {}) {
  return withLock(() => {
    const record = readRecord();
    const item = record.items.find((entry) => entry.name === name);
    if (!item) throw new Error(`「${name}」は自分で追加したスキルにありません`);
    if (!force && changedLocally(item)) throw new Error(`「${name}」は手元で変えているので消していません`);
    const removed = item.agents.map((agent) => skillDir(agent, item.name));
    return changeSkills(null, removed, () => {
      writeRecord({ ...record, items: record.items.filter((entry) => entry !== item) });
      return { name, removed };
    });
  });
}

// ── 入口 ─────────────────────────────────────────────────────

function parseArgs(argv) {
  const args = [];
  let path = "";
  let force = false;
  let expectedCommit;
  let expectedName;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--path") path = argv[(i += 1)] ?? "";
    else if (argv[i] === "--force") force = true;
    else if (argv[i] === "--expect-commit") expectedCommit = argv[(i += 1)] ?? "";
    else if (argv[i] === "--expect-name") expectedName = argv[(i += 1)] ?? "";
    else args.push(argv[i]);
  }
  return { args, path, force, expectedCommit, expectedName };
}

function summarize(results) {
  const updated = results.filter((result) => result.outcome === "updated").length;
  const failed = results.filter((result) => result.outcome === "failed").length;
  const kept = results.filter((result) => result.outcome === "kept").length;
  if (failed) return `${failed}件は更新できませんでした`;
  if (updated) return `${updated}件を更新`;
  return kept ? "手元で変えているものは更新していません" : "すべて最新";
}

const print = (value) => process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);

function main(argv) {
  const [command, ...rest] = argv;
  const { args, path, force, expectedCommit, expectedName } = parseArgs(rest);
  if (command === "preview") return print(preview(args[0], path));
  if (command === "add") {
    const item = add(args[0], path, { expectedCommit, expectedName });
    return console.log(`${item.name}（${item.version}）を入れました`);
  }
  if (command === "check") return print(check());
  if (command === "list") return print(readRecord().items);
  if (command === "remove") return console.log(`${remove(args[0], { force }).name} を外しました`);
  if (command === "update") {
    const results = update();
    for (const result of results) if (result.text) console.log(result.text);
    console.log(summarize(results));
    if (results.some((result) => result.outcome === "failed")) process.exitCode = 1;
    return undefined;
  }
  process.stderr.write("使い方: mulmo-my-tools.mjs preview|add|check|update|remove|list\n");
  process.exitCode = 2;
  return undefined;
}

const invoked = process.argv[1] ? pathToFileURL(realpathSync(process.argv[1])).href : "";
if (invoked === import.meta.url) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
