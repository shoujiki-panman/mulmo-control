#!/bin/zsh
set -eu

# 手元でビルドして、いま動いているアプリを差し替える。**見た目を確かめる用。**
#
#   ./try.sh            いまのブランチを pull してビルドし、入れる
#   ./try.sh main       main に切り替えてから同じことをする
#   ./try.sh <branch>   そのブランチで
#
# release.sh は配るためのもの（版上げ・署名・公証・タグ・push）。こちらは
# **自分の Mac に入れるだけ**で、配ったものには触らない。
#
# ## なぜこれが要るか
#
# 2026-09-11、この手順を手で6回やって3回失敗した（Issue #192〜#194）。どれも
# 「入れ替わったつもり」で終わって、古い画面を見ながら「変わらない」と
# 言い合っていた。踏んだ穴は3つ。
#
#   1. ビルドが失敗しても `;` で繋いだ後半が走り、**古い build/ が黙って入った**
#   2. 古いプロセスが生きたまま `open` して、**前の画面が出続けた**
#      （メニューバーアプリは .app を置き換えても、動いている本体は入れ替わらない）
#   3. main を pull していて、**ブランチの変更が入っていなかった**
#
# 手順を紙に書いて渡す限り、この3つは毎回起きる。script にして、失敗したら
# 止まり、最後に**入れたものを名乗らせる**。

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

APP="/Applications/Mulmo Control.app"
BIN="MulmoControl"

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '  ✓ %s\n' "$1"; }

# ── 1. ソースを揃える ────────────────────────────────────────
step "ソース"
if [ -n "${1:-}" ]; then
  git checkout "$1"
fi
BRANCH="$(git branch --show-current)"
[ -n "${BRANCH}" ] || fail "ブランチにいません（detached HEAD）。./try.sh main のようにブランチ名を渡してください"
git pull --ff-only origin "${BRANCH}"
COMMIT="$(git log --oneline -1)"
ok "${BRANCH} / ${COMMIT}"

# ── 2. ビルド。失敗したらここで止まる（穴1）───────────────────
step "ビルド"
./build-app.sh >/dev/null
[ -x "build/Mulmo Control.app/Contents/MacOS/${BIN}" ] || fail "ビルドの成果物が見つかりません"
ok "build/Mulmo Control.app"

# ── 3. 動いているものを止め、止まったことを確かめる（穴2）───────
step "いまのアプリを止める"
killall "${BIN}" 2>/dev/null || true
waited=0
while pgrep -x "${BIN}" >/dev/null 2>&1; do
  waited=$(( waited + 1 ))
  [ "${waited}" -lt 20 ] || { killall -9 "${BIN}" 2>/dev/null || true; sleep 1; }
  [ "${waited}" -lt 30 ] || fail "${BIN} が止まりません。アクティビティモニタで落としてから、もう一度"
  sleep 0.5
done
ok "止まった"

# ── 4. 差し替えて起こす ──────────────────────────────────────
step "差し替え"
# 消す先は綴りで書く。check.sh の許可一覧が綴りで見ているので、変数にすると
# 「許可していない rm -rf」として落ちる（uninstall.sh と同じ書き方）。
rm -rf "/Applications/Mulmo Control.app"
ditto --norsrc --noextattr "build/Mulmo Control.app" "${APP}"
open "${APP}"
sleep 2
pgrep -x "${BIN}" >/dev/null 2>&1 || fail "起こしたのに動いていません。ログ: Console.app で ${BIN} を探してください"
ok "動いている"

# ── 5. 入れたものを名乗る（穴3）──────────────────────────────
printf '\n\033[32m✓ 入れました\033[0m\n'
printf '   %s\n' "${COMMIT}"
printf '   %s\n' "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist" 2>/dev/null | sed 's/^/版 /')"
printf '\n   メニューバーから開いて見てください。\n'
printf '   \033[33m「アプリ更新」を押すと配布版に戻ります。\033[0m 見終わるまで押さないこと。\n'
