#!/bin/zsh
set -eu

# リリースを1コマンドで出す（Issue #14）。
#
#   ./release.sh 1.0.14                 リリースノートをエディタで書く
#   ./release.sh 1.0.14 -F notes.md     ファイルから読む
#   ./release.sh 1.0.14 --dry-run       出さずに、ビルドと検証だけ通す
#
# 手作業だった build-app.sh → ditto → gh release create をまとめただけでなく、
# 毎回やるべき確認も同じ場所に入れてある。v1.0.9 では配信物を確かめずに出して、
# ほとんどのボタンが動かない版を配ってしまった。順番と確認を人の記憶に
# 頼らないための script。

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
  echo "使い方: ./release.sh X.Y.Z [--dry-run] [-F notes.md]" >&2
  exit 1
fi
shift

DRY_RUN=0
NOTES_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    *) NOTES_ARGS+=("$1"); shift ;;
  esac
done

if ! printf '%s' "${VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "バージョンは X.Y.Z の形で渡してください（受け取った値: ${VERSION}）" >&2
  exit 1
fi

TAG="v${VERSION}"
step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '  ✓ %s\n' "$1"; }

# ── 出す前の前提を全部ここで落とす ───────────────────────────────
step "前提を確認"

command -v gh >/dev/null 2>&1 || fail "gh が要ります"
[ -z "$(git status --porcelain)" ] || fail "コミットしていない変更があります"

git fetch origin --quiet --tags
# ブランチ名ではなく中身で判定する。worktree では detached HEAD から出すことも
# あるので、「main という名前か」より「origin/main と同じコミットか」が本質。
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || fail "origin/main と差があります（HEAD: $(git rev-parse --short HEAD) / origin/main: $(git rev-parse --short origin/main)）。pull / push してください"
git rev-parse "${TAG}" >/dev/null 2>&1 && fail "タグ ${TAG} は既にあります"

LATEST="$(git ls-remote --tags --refs origin 2>/dev/null \
  | /usr/bin/awk -F'refs/tags/v' 'NF > 1 { print $2 }' | /usr/bin/sort -V | /usr/bin/tail -1)"
if [ -n "${LATEST}" ]; then
  NEWER="$(printf '%s\n%s\n' "${VERSION}" "${LATEST}" | /usr/bin/sort -V | /usr/bin/tail -1)"
  [ "${NEWER}" = "${VERSION}" ] || fail "${VERSION} は既存の最新 ${LATEST} より古いです"
fi
ok "main はクリーンで origin と一致（前回: ${LATEST:-なし} → 今回: ${VERSION}）"

# ── Info.plist を書き換えてコミット ─────────────────────────────
step "Info.plist を ${VERSION} にする"

CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
BUILD_NO="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
if [ "${CURRENT}" = "${VERSION}" ]; then
  ok "既に ${VERSION}（書き換えなし）"
else
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD_NO + 1))" Info.plist
  plutil -lint Info.plist >/dev/null || fail "Info.plist が壊れました"
  ok "${CURRENT} → ${VERSION}（build ${BUILD_NO} → $((BUILD_NO + 1))）"
fi

# ── npm パッケージの版も合わせる ────────────────────────────────
step "package.json を ${VERSION} にする"

# インストーラは常に最新リリースを取りに行くので、npm 上の版が古くても
# 入るアプリは新しい。ただし npm のページを見た人は「1.0.18 が最新」と
# 読むので、番号は揃えておく。
NPM_CURRENT="$(node -p "require('./package.json').version")"
if [ "${NPM_CURRENT}" = "${VERSION}" ]; then
  ok "既に ${VERSION}"
else
  node -e "const f='package.json',j=require('./'+f);j.version=process.argv[1];require('fs').writeFileSync(f,JSON.stringify(j,null,2)+'\n')" "${VERSION}"
  ok "${NPM_CURRENT} → ${VERSION}"
fi

# ── ビルドして、配る前に中身を確かめる ──────────────────────────
step "ビルド"
APP="$("${ROOT}/build-app.sh")"
ok "$(basename "${APP}")"

step "配る前の検証"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
[ "${BUILT_VERSION}" = "${VERSION}" ] || fail "ビルド結果の版が ${BUILT_VERSION} です（期待: ${VERSION}）"
ok "版 ${BUILT_VERSION}"

SCRIPT_COUNT="$(ls "${APP}/Contents/Resources/scripts" 2>/dev/null | wc -l | tr -d ' ')"
SOURCE_COUNT="$(ls "${ROOT}/scripts" | wc -l | tr -d ' ')"
[ "${SCRIPT_COUNT}" = "${SOURCE_COUNT}" ] || fail "同梱スクリプトが ${SCRIPT_COUNT} 本です（scripts/ には ${SOURCE_COUNT} 本）"
ok "同梱スクリプト ${SCRIPT_COUNT} 本"

codesign --verify --deep --strict "${APP}" 2>/dev/null || fail "署名が通りません"
ok "署名"

# アプリのパスには空白がある。コマンド組み立てで引用が漏れるとここで落ちる
# （v1.0.9 の回帰。Issue #32）。
/bin/zsh -c "\"${APP}/Contents/Resources/scripts/mulmoclaude-status\" >/dev/null" \
  || fail "同梱スクリプトを空白入りパスから実行できません"
ok "空白入りパスからの実行"

step "zip を作る"
ZIP="${ROOT}/build/MulmoControl.zip"
rm -f "${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
ok "$(du -h "${ZIP}" | cut -f1 | tr -d ' ')"

if [ "${DRY_RUN}" = "1" ]; then
  printf '\n\033[33m--dry-run なのでここまで。%s は作っていません。\033[0m\n' "${TAG}"
  git checkout -- Info.plist package.json 2>/dev/null || true
  exit 0
fi

# ── ここから戻せない操作 ────────────────────────────────────────
step "コミットして push"
if [ -n "$(git status --porcelain Info.plist package.json)" ]; then
  git add Info.plist package.json
  git commit -q -m "Bump to ${VERSION}

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  git push -q origin HEAD:main
  ok "Bump to ${VERSION}"
else
  ok "コミットするものなし"
fi

step "リリースを作る"
if [ ${#NOTES_ARGS[@]} -gt 0 ]; then
  gh release create "${TAG}" "${ZIP}" --title "Mulmo Control ${VERSION}" --target main "${NOTES_ARGS[@]}"
else
  gh release create "${TAG}" "${ZIP}" --title "Mulmo Control ${VERSION}" --target main
fi
ok "${TAG}"

# ── 出したものを、利用者と同じ経路で取り直して確かめる ──────────
step "配信されたものを確認"
CHECK_DIR="$(mktemp -d /private/tmp/mulmo-release-check.XXXXXX)"
trap 'rm -rf "${CHECK_DIR}"' EXIT
curl -fsSL --connect-timeout 20 -o "${CHECK_DIR}/MulmoControl.zip" \
  "https://github.com/shoujiki-panman/mulmo-control/releases/latest/download/MulmoControl.zip" \
  || fail "配信された zip を取得できません"
ditto -x -k "${CHECK_DIR}/MulmoControl.zip" "${CHECK_DIR}"

PUBLISHED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${CHECK_DIR}/Mulmo Control.app/Contents/Info.plist")"
[ "${PUBLISHED}" = "${VERSION}" ] || fail "配信されているのは ${PUBLISHED} です（期待: ${VERSION}）"
ok "latest が返すのは ${PUBLISHED}"

PUBLISHED_SCRIPTS="$(ls "${CHECK_DIR}/Mulmo Control.app/Contents/Resources/scripts" | wc -l | tr -d ' ')"
[ "${PUBLISHED_SCRIPTS}" = "${SOURCE_COUNT}" ] || fail "配信物の同梱スクリプトが ${PUBLISHED_SCRIPTS} 本です"
codesign --verify --deep --strict "${CHECK_DIR}/Mulmo Control.app" 2>/dev/null || fail "配信物の署名が通りません"
ok "同梱スクリプト ${PUBLISHED_SCRIPTS} 本・署名"

# npm 側は bin/ が変わったときだけ出し直せばよい。インストーラは常に最新
# リリースを取りに行くので、版が古くても入るアプリは新しい。
if [ "$(npm view mulmo-control version 2>/dev/null)" != "${VERSION}" ]; then
  printf '\n\033[33m! npm 上の版が古いままです（%s）。番号を揃えるなら:\033[0m\n' \
    "$(npm view mulmo-control version 2>/dev/null || echo '取得できず')"
  printf '    npm publish\n'
  printf '  bin/ を変えていないなら、急ぐ必要はありません。\n'
fi

printf '\n\033[32m✓ %s を公開しました\033[0m\n' "${TAG}"
printf '  https://github.com/shoujiki-panman/mulmo-control/releases/tag/%s\n' "${TAG}"
printf '  利用者はメニューバーの アプリ更新 から入れられます\n'
