#!/bin/zsh
set -eu

# 配る前に確かめること。
#
#   ./check.sh              ビルドしてから全部確かめる
#   ./check.sh --no-build   既にある build/ を確かめる（release.sh 用）
#
# release.sh と GitHub Actions の両方がここを呼ぶ。同じことを2箇所に書くと、
# 片方だけ直して安心する事故が起きるので、1箇所にまとめてある。
#
# ここに入っているのは全部、実際に配ってから見つかった不具合の再発よけ。
# 「壊れていることに気づくのが遅い」のが積年の問題なので、気づく場所を
# リリースの瞬間から PR の時点まで前倒しするのが狙い。

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

CLEANUP_DIRS=()
cleanup() {
  for dir in "${CLEANUP_DIRS[@]}"; do
    [ -n "${dir}" ] && rm -rf "${dir}"
  done
}
trap cleanup EXIT

make_tmp_dir() {
  local name="$1"
  local dir
  dir="$(mktemp -d "/private/tmp/${name}.XXXXXX")"
  CLEANUP_DIRS+=("${dir}")
  printf '%s' "${dir}"
}

BUILD=1
[ "${1:-}" = "--no-build" ] && BUILD=0

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '  ✓ %s\n' "$1"; }

# ── シェルスクリプト ────────────────────────────────────────────
step "スクリプトの構文"
for f in "${ROOT}/scripts"/* "${ROOT}"/*.sh; do
  [ -f "$f" ] || continue
  case "$f" in *.mjs|*.md) continue ;; esac
  head -1 "$f" | grep -q '^#!' || continue
  zsh -o no_bg_nice -n "$f" || fail "構文が壊れています: $(basename "$f")"
done
ok "$(ls "${ROOT}/scripts" | wc -l | tr -d ' ') 本 + ルートの .sh"

# ── 置き場所の約束 ──────────────────────────────────────────────
step "同梱スクリプトの自己完結"

# install.sh を通していない Mac でも動く必要がある（Issue #51）。
# ~/.local/bin は install.sh がコピーして初めて存在するので、兄弟スクリプトを
# そこから呼んでいると zip だけで入れた人が動かせない。
if grep -rn '\.local/bin/mulmoterminal-' "${ROOT}/scripts" 2>/dev/null; then
  fail "兄弟スクリプトを ~/.local/bin から呼んでいます。SCRIPT_DIR を使ってください（Issue #51）"
fi
ok "兄弟スクリプトを ~/.local/bin から呼んでいない"

# launchd の GUI ドメインはロケール変数を持たない。起動スクリプトが補わないと、
# 自動起動した MulmoTerminal では tmux が非 UTF-8 経路に落ち、日本語が
# 1 セルにつき `_` 1 個に潰れる（Issue #62 / receptron/mulmoterminal#1634）。
# 症状が出るのは自動起動のときだけで、ターミナルから手で起動すると継承するので
# 出ない。うっかり消しても手元では気づけないため、ここで止める。
#
# 変数名で探すとロケールの話をしているコメント自体に当たって、コードを消しても
# 通ってしまう。行頭の export だけを見る（コメント行は # で始まるので当たらない）。
if ! grep -qE '^[[:space:]]*export LANG=' "${ROOT}/scripts/start-mulmoterminal.sh"; then
  fail "起動スクリプトにロケール補完がありません（Issue #62）"
fi
ok "起動スクリプトがロケールを補っている"

# アプリのパスには空白がある（/Applications/Mulmo Control.app）。
# コマンド文字列に裸で埋めると /Applications/Mulmo で切れる（Issue #32）。
#
# toolsDir を文字列に埋めてよい箇所は1つも無い。必ず tool() を通す。
# 定義そのもの（private func tool）だけ除く。
BARE="$(grep -n 'toolsDir)' "${ROOT}/Sources/main.swift" | grep -v 'private func tool' || true)"
if [ -n "${BARE}" ]; then
  printf '%s\n' "${BARE}"
  fail "toolsDir を裸で埋め込んでいます。tool() を通してください（Issue #32）"
fi

# localBin は例外がある。次の3つは正しい形なので除く。
#   - FileManager に渡す本物のパス（引用すると名前の一部になる）
#   - ディレクトリ自体を渡すもの: "\(localBin)" のように直後が閉じ引用符
#   - 複数行のシェル文字列の中で ln -sf の宛先になっているもの
# 逆に "\(localBin)/コマンド名" の形は、引用符があっても駄目。文字列全体を
# zsh に渡すので、パスに空白があればそこで切れる（#32 で実際に起きた）。
BARE_BIN="$(grep -n 'localBin)' "${ROOT}/Sources/main.swift" \
  | grep -v 'private func bin' \
  | grep -v 'isExecutableFile\|let localPath' \
  | grep -v '"\\(localBin)"' \
  | grep -v 'ln -sf' || true)"
if [ -n "${BARE_BIN}" ]; then
  printf '%s\n' "${BARE_BIN}"
  fail "localBin を裸で埋め込んでいます。bin() を通してください（Issue #32）"
fi
ok "コマンド文字列は tool() / bin() を通している"

# 置き場所を ~/Documents/Codex から移した（Issue #4）。1箇所でも戻ると
# 「アプリは新しい場所を読み、スクリプトは古い場所に書く」形になり、
# 画面が「未確認」に落ちる。実際に一度やっている。
LEGACY="$(grep -rn 'Documents/Codex' "${ROOT}/Sources/main.swift" "${ROOT}/scripts" \
  "${ROOT}/install.sh" "${ROOT}/bin" 2>/dev/null \
  | grep -v 'legacyLogDir\|let legacy ' \
  | grep -v ':[0-9]*: *//\|:[0-9]*: *#' || true)"
if [ -n "${LEGACY}" ]; then
  printf '%s\n' "${LEGACY}"
  fail "~/Documents/Codex を参照しています。logDir を使ってください（Issue #4）"
fi
ok "~/Documents/Codex を参照していない"

# ── セキュリティの回帰よけ ────────────────────────────────────────
step "設定ファイルと更新経路の安全性"

SECURITY_FILES=(
  "${ROOT}/scripts"/*
  "${ROOT}/install.sh"
  "${ROOT}/uninstall.sh"
  "${ROOT}/build-app.sh"
  "${ROOT}/release.sh"
)

CONFIG_SOURCE="$(grep -RInE '^[[:space:]]*(source|\.)[[:space:]]+"?\$\{CONFIG\}"?' "${SECURITY_FILES[@]}" 2>/dev/null || true)"
if [ -n "${CONFIG_SOURCE}" ]; then
  printf '%s\n' "${CONFIG_SOURCE}"
  fail "app-info.env を shell として実行しています。値だけを読む parser を使ってください"
fi
ok "app-info.env を shell として実行していない"

SECURITY_TMP="$(make_tmp_dir "mulmo-control-security")"
mkdir -p "${SECURITY_TMP}/Library/Application Support/Mulmo Control"
PWNED="${SECURITY_TMP}/pwned"
cat > "${SECURITY_TMP}/Library/Application Support/Mulmo Control/app-info.env" <<INFO
MULMO_CONTROL_REPO_URL='https://example.invalid/repo.git'
touch '${PWNED}'
MULMO_CONTROL_SOURCE_DIR='/tmp/source'\''quote'
MULMO_CONTROL_BRANCH='release'
INFO
CONFIG_JSON="$(HOME="${SECURITY_TMP}" MULMO_CONTROL_TEST_PRINT_CONFIG=1 "${ROOT}/scripts/mulmo-control-self-update")"
[ ! -e "${PWNED}" ] || fail "app-info.env の中身が shell として実行されました"
CONFIG_JSON="${CONFIG_JSON}" /usr/bin/python3 - <<'PY' || fail "app-info.env の値を正しく読めません"
import json
import os

data = json.loads(os.environ["CONFIG_JSON"])
assert data["repoUrl"] == "https://example.invalid/repo.git"
assert data["sourceDir"] == "/tmp/source'quote"
assert data["branch"] == "release"
PY
ok "app-info.env を値としてだけ読める"

NETWORK_PIPE="$(grep -RInE '\b(curl|wget)\b[^|]*\|[[:space:]]*(sh|bash|zsh)\b' "${SECURITY_FILES[@]}" 2>/dev/null \
  | grep -v ':[0-9]*:[[:space:]]*#' || true)"
if [ -n "${NETWORK_PIPE}" ]; then
  printf '%s\n' "${NETWORK_PIPE}"
  fail "ネットワーク取得結果を shell に直接流しています"
fi
ok "ネットワーク取得結果を shell に直接流していない"

EVAL_OR_SUDO="$(grep -RInE '\b(eval|sudo)\b' "${SECURITY_FILES[@]}" 2>/dev/null \
  | grep -v ':[0-9]*:[[:space:]]*#' || true)"
if [ -n "${EVAL_OR_SUDO}" ]; then
  printf '%s\n' "${EVAL_OR_SUDO}"
  fail "eval / sudo を使っています"
fi
ok "eval / sudo を使っていない"

# ── ビルドと配布物 ──────────────────────────────────────────────
if [ "${BUILD}" = "1" ]; then
  step "ビルド"
  APP="$("${ROOT}/build-app.sh")"
  ok "$(basename "${APP}")"
else
  APP="${ROOT}/build/Mulmo Control.app"
  [ -d "${APP}" ] || fail "build/ にアプリがありません"
fi

step "配布物"

VERIFY_DIR="$(make_tmp_dir "mulmo-control-verify")"
VERIFY_APP="${VERIFY_DIR}/Mulmo Control.app"
ditto "${APP}" "${VERIFY_APP}"
xattr -cr "${VERIFY_APP}" 2>/dev/null || true

SOURCE_COUNT="$(ls "${ROOT}/scripts" | wc -l | tr -d ' ')"
BUNDLED_COUNT="$(ls "${APP}/Contents/Resources/scripts" 2>/dev/null | wc -l | tr -d ' ')"
[ "${BUNDLED_COUNT}" = "${SOURCE_COUNT}" ] \
  || fail "同梱スクリプトが ${BUNDLED_COUNT} 本です（scripts/ には ${SOURCE_COUNT} 本）"
ok "同梱スクリプト ${BUNDLED_COUNT} 本"

codesign --verify --deep --strict "${VERIFY_APP}" 2>/dev/null || fail "署名が通りません"
ok "署名"

# v1.0.9 はここが抜けていて、ほとんどのボタンが動かない版を配った。
/bin/zsh -c "\"${APP}/Contents/Resources/scripts/mulmoclaude-status\" >/dev/null" \
  || fail "同梱スクリプトを空白入りパスから実行できません（Issue #32）"
ok "空白入りパスからの実行"

# ── npm パッケージ ──────────────────────────────────────────────
step "npm パッケージ"
node --check "${ROOT}/bin/mulmo-control.mjs" || fail "bin/mulmo-control.mjs の構文が壊れています"
ok "bin/mulmo-control.mjs"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/Info.plist")"
PKG_VERSION="$(node -p "require('${ROOT}/package.json').version")"
[ "${APP_VERSION}" = "${PKG_VERSION}" ] \
  || fail "Info.plist が ${APP_VERSION}、package.json が ${PKG_VERSION} でずれています"
ok "版が揃っている（${APP_VERSION}）"

printf '\n\033[32m✓ 全部通りました\033[0m\n'
