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
  zsh -n "$f" || fail "構文が壊れています: $(basename "$f")"
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

# git stash pop はぶつかると、失敗を返しながら作業ツリーにコンフリクトマーカーを
# 書き込んで止まる。それを見ずに先へ進むと、壊れた package.json のまま起動して
# 「更新しました」と報告してしまう（Issue #66）。検出だけ残して停止を消しても
# 同じことが起きるので、両方を見る。
# コメント行は除く。変数名や説明文で検査を満たせてはいけない（#62 で踏んだ）。
UPD="$(grep -vE '^[[:space:]]*#' "${ROOT}/scripts/mulmoclaude-update-latest")"
if ! printf '%s\n' "${UPD}" | grep -q 'diff-filter=U'; then
  fail "更新スクリプトが stash pop のコンフリクトを見ていません（Issue #66）"
fi
if ! printf '%s\n' "${UPD}" | grep -q 'RESTORE_STATUS'; then
  fail "コンフリクトを検出しても止まっていません（Issue #66）"
fi
ok "更新スクリプトが stash pop のコンフリクトで止まる"

# install-agent は plist を書くだけで Agent を止めない。起こし直さないと、
# 直したものを配っても走っているプロセスには届かない（Issue #65）。
# これも作者の環境では起きない（確認のたびに手で起動し直すため）。
if ! grep -vE '^[[:space:]]*#' "${ROOT}/install.sh" | grep -q 'mulmoterminal-restart'; then
  fail "起動設定が変わっても MulmoTerminal を起こし直していません（Issue #65）"
fi
ok "起動設定が変わったら MulmoTerminal を起こし直す"

# 待っても変わらない失敗まで再試行すると、利用者には「回線の不調かも」という
# 誤った見立てだけが残る（Issue #71）。作者は存在するパッケージしか入れないので、
# この経路は自分では踏まない。
if ! grep -vE '^[[:space:]]*#' "${ROOT}/scripts/mulmo-npm-install" | grep -q 'E404'; then
  fail "存在しないパッケージでも回線のせいにしています（Issue #71）"
fi
ok "npm の 404 を回線のせいにしない"

# ポートは mulmoterminal-agent-env と main.swift の mtPort の2箇所だけが持つ
# （Issue #7）。他所に数字を書くと、MULMOTERMINAL_PORT で逃がしたつもりでも
# 一部だけ 34567 のまま動くという、最も気づきにくい壊れ方をする。
#
# コメント判定は grep -v で書いてはいけない。`:[[:space:]]*(#|//)` は URL の
# `://` に当たり、ポートは必ず URL の中にあるので検査が丸ごと無効になる。
# file:line: を落としてから、行頭が # や // かを見る。
STRAY_PORT="$(grep -rn '34567' "${ROOT}/scripts" "${ROOT}/Sources/main.swift" 2>/dev/null \
  | grep -v 'mulmoterminal-agent-env' \
  | grep -v 'private let mtPort' \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*(#|\/\/)/) print }' || true)"
if [ -n "${STRAY_PORT}" ]; then
  printf '%s\n' "${STRAY_PORT}"
  fail "ポートを直書きしています（Issue #7）"
fi
ok "ポートの既定は1箇所だけが持つ"

# 配るものの識別子に作者名を戻さない（Issue #7）。旧ラベルは agent-env の
# 移行リストにだけ残す。
STRAY_LABEL="$(grep -rn 'com\.shutanuma\.mulmoterminal' "${ROOT}/scripts" "${ROOT}/Sources/main.swift" 2>/dev/null \
  | grep -v 'MULMO_AGENT_LEGACY_LABELS' || true)"
if [ -n "${STRAY_LABEL}" ]; then
  printf '%s\n' "${STRAY_LABEL}"
  fail "旧ラベルが移行リスト以外に残っています（Issue #7）"
fi
ok "LaunchAgent のラベルに作者名が入っていない"

# 常駐して初めて機能するアプリなので、ログイン時起動は既定で入れる（Issue #75）。
# ただし印は専用の鍵で持つ。初回アナウンス（#9）の鍵に相乗りすると、既に一度でも
# 起動したことがある人には永遠に効かない。
SW="$(grep -vE '^[[:space:]]*(//|/\*|\*)' "${ROOT}/Sources/main.swift")"
if ! printf '%s\n' "${SW}" | grep -q 'launch-at-login-defaulted'; then
  fail "ログイン時起動が既定で入りません（Issue #75）"
fi
if printf '%s\n' "${SW}" | grep -q 'first-launch-announced.*launch\|launchAtLogin.*first-launch-announced'; then
  fail "初回アナウンスの鍵に相乗りしています。既存利用者に効きません（Issue #75）"
fi
ok "ログイン時起動を初回に1回だけ入れる"

# 画面に出す値は、実際に効いているものから取る。
#
# keepalive-enabled は起動/停止ボタンが作ったり消したりするだけで、読み手は
# 画面表示しかいなかった。自動起動を決めているのは plist の RunAtLoad と
# KeepAlive で、このファイルとは無関係。入れただけで一度も起動ボタンを押して
# いない人には、自動起動するのに「オフ」と表示されていた。作者は必ず押すので
# 遭遇しない類。同じものを作り直さないためのガード。
STRAY_FLAG="$(grep -rn 'keepalive-enabled' "${ROOT}/scripts" "${ROOT}/Sources/main.swift" 2>/dev/null \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*(#|\/\/)/) print }' || true)"
if [ -n "${STRAY_FLAG}" ]; then
  printf '%s\n' "${STRAY_FLAG}"
  fail "実体のない状態フラグが復活しています"
fi
ok "自動起動の表示に作り物のフラグを使っていない"

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

SOURCE_COUNT="$(ls "${ROOT}/scripts" | wc -l | tr -d ' ')"
BUNDLED_COUNT="$(ls "${APP}/Contents/Resources/scripts" 2>/dev/null | wc -l | tr -d ' ')"
[ "${BUNDLED_COUNT}" = "${SOURCE_COUNT}" ] \
  || fail "同梱スクリプトが ${BUNDLED_COUNT} 本です（scripts/ には ${SOURCE_COUNT} 本）"
ok "同梱スクリプト ${BUNDLED_COUNT} 本"

codesign --verify --deep --strict "${APP}" 2>/dev/null || fail "署名が通りません"
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
