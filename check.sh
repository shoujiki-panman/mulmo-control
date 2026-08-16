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

# ── シェルの安全 ────────────────────────────────────────────────
# SECURITY.md の C 節（021〜027）。どれも「実測はした」だけで自動検査が
# 無く、明日誰かが壊しても気づけない状態だった。
step "シェルの安全"

# grep -rn の結果から `file:line:` を落とし、コメント行を捨てる。
# 語で探すと、その話をしている自分のコメントに当たる（#83 で踏んだ罠）。
noncomment() {
  awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }'
}

# 021 シェバンが無いファイルは、上の構文検査が黙って飛ばす。
# 「検査に通った」ではなく「検査されなかった」なので、ここで落とす。
for f in "${ROOT}/scripts"/* "${ROOT}"/*.sh; do
  [ -f "$f" ] || continue
  case "$f" in *.mjs|*.md) continue ;; esac
  head -1 "$f" | grep -q '^#!' || fail "シェバンがありません: $(basename "$f")（構文検査ごと飛ばされます）"
done
ok "全スクリプトにシェバンがある"

# 022 未定義の変数をそのまま使うと、パスが空文字になって思わぬ場所を触る。
# mulmoterminal-agent-env だけは source される定義ファイルなので対象外。
for f in "${ROOT}/scripts"/* "${ROOT}"/*.sh; do
  [ -f "$f" ] || continue
  case "$f" in *.mjs|*.md|*/mulmoterminal-agent-env) continue ;; esac
  head -1 "$f" | grep -q '^#!' || continue
  grep -qE '^[[:space:]]*set -(u|eu|ue)' "$f" ||
    fail "set -u がありません: $(basename "$f")"
done
ok "set -u / set -eu がある"

# 023〜025 落としてきたものをそのまま実行する形、shell への丸投げ、権限昇格。
# どれもこのリポジトリには1つも無い。増えたら気づきたい。
#
# check.sh 自身は対象から外す。探している語がこのファイルには必ず書いてあり、
# 自分の検査文に当たるため（#83 で踏んだ罠と同じ形）。check.sh は配布物では
# ないので（同梱されるのは scripts/ だけ）、外しても利用者には届かない。
SAFETY_TARGETS=("${ROOT}/scripts")
for f in "${ROOT}"/*.sh; do
  case "$f" in */check.sh) continue ;; esac
  SAFETY_TARGETS+=("$f")
done

for pat in 'curl[^|]*|[[:space:]]*\(sh\|zsh\|bash\)' 'wget[^|]*|[[:space:]]*\(sh\|zsh\|bash\)'; do
  HIT="$(grep -rn "${pat}" "${SAFETY_TARGETS[@]}" 2>/dev/null | noncomment || true)"
  [ -z "${HIT}" ] || { printf '%s\n' "${HIT}"; fail "落としたものを直接 shell に流しています"; }
done
for word in eval sudo; do
  HIT="$(grep -rnw "${word}" "${SAFETY_TARGETS[@]}" 2>/dev/null | noncomment || true)"
  [ -z "${HIT}" ] || { printf '%s\n' "${HIT}"; fail "${word} を使っています"; }
done
ok "落としたものの丸投げ・eval・権限昇格がない"

# 026/027 消す対象は数えられるほど少ないので、許すものを並べる形にする。
# 禁止する形を並べると綴りの数だけ穴が開く（#83 で実測した）。
RMRF="$(grep -rn 'rm -rf\|rm -fr' "${SAFETY_TARGETS[@]}" 2>/dev/null | noncomment \
  | grep -v '"/Applications/Mulmo Control.app"' \
  | grep -v '"${APP_DIR}/Contents/Resources/scripts"' \
  | grep -v '"${CHECK_DIR}"' || true)"
if [ -n "${RMRF}" ]; then
  printf '%s\n' "${RMRF}"
  fail "許可していない rm -rf があります。消す対象を check.sh の一覧に足してください"
fi
ok "rm -rf の対象は決まった3つだけ"

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

# ポートを持っているだけのプロセスを、確かめずに落とさない（Issue #91）。
#
# 5173 は Vite の既定ポートなので、他のプロジェクトを開いているだけで一致する。
# 以前の停止は SIGTERM の2秒後に SIGKILL まで行っていたので、巻き添えになった
# 側は保存の機会もなかった。作業ディレクトリで自分のものだけを選ぶ
# mulmoclaude-pids を通す。
#
# ここも whitelist で書く。「lsof を直に叩いていないか」を見るので、綴りを
# 増やされても効く（#83）。pids 自身と、表示だけの status は対象外。
#
# `-tiTCP:` と `-iTCP:` の両方があるので、ダッシュから書くと片方に当たらない。
# 最初 `-iTCP:` と書いて、検査が丸ごと効いていなかった。
PORT_KILL="$(grep -rn 'lsof[^|]*iTCP:\(5173\|3001\)' "${ROOT}/scripts" 2>/dev/null \
  | grep -v 'scripts/mulmoclaude-pids:' \
  | grep -v 'scripts/mulmoclaude-status:' \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }' || true)"
if [ -n "${PORT_KILL}" ]; then
  printf '%s\n' "${PORT_KILL}"
  fail "MulmoClaude のポートを直に見ています。mulmoclaude-pids を通してください（Issue #91）"
fi
ok "他人のプロセスを巻き添えにしない"

# 設定ファイルを shell として実行しない（Issue #67）。
#
# `. "${CONFIG}"` / `source "${CONFIG}"` は、app-info.env に紛れた
# `touch ...` や `$(...)` を読んだ側の権限でそのまま走らせる。実測でも
# `touch /tmp/...` の行が実行された。値は mulmo-config-get 経由で読む。
#
# このガードが無いと、事情を知らない担当がまた増やす。実際、#78 の作業で
# 1本増えた（このIssueを読まずに作業していた）。
#
# 最初は `"${CONFIG}"` という綴りを探す形で書いたが、それは 5通りの書き方のうち
# 1通りしか見ていなかった（Issue #83 で実測）。`$CONFIG`、変数名違い、パス直書き、
# 一行の `&&` は全部素通りする。禁止したい綴りを並べる形では勝てない。
#
# なので whitelist にする。このリポジトリで `.` / `source` してよいものは
# `mulmoterminal-agent-env` の1つだけ（実測: scripts/ 9本 + install.sh + uninstall.sh）。
# それ以外を読み込んでいたら落とす。綴りにも変数名にも依存しない。
SOURCED="$(grep -rn '\(^[[:space:]]*\|[;&|][[:space:]]*\)\(\.\|source\)[[:space:]]\+[^[:space:];&|]' \
  "${ROOT}/scripts" "${ROOT}/install.sh" "${ROOT}/uninstall.sh" 2>/dev/null \
  | grep -v 'mulmoterminal-agent-env' \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }' || true)"
if [ -n "${SOURCED}" ]; then
  printf '%s\n' "${SOURCED}"
  fail "設定ファイルを shell として実行しています。値は mulmo-config-get で読んでください（Issue #67 / #83）"
fi
ok "設定ファイルを shell として実行していない"

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

# 上のガードは「古い場所に戻っていないか」しか見ない。3つ目の場所が増えるのは
# 素通りする（`Library/Logs/MulmoControl` のような空白なしの綴りなど）。
# 置き場所は1つだけと決めているので、許すものを並べる形にする（#83 の教訓）。
STRAY_LOG="$(grep -rn 'Library/Logs/' "${ROOT}/Sources/main.swift" "${ROOT}/scripts" \
  "${ROOT}/install.sh" "${ROOT}/bin" 2>/dev/null \
  | grep -v 'Library/Logs/Mulmo Control' \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*(#|\/\/)/) print }' || true)"
if [ -n "${STRAY_LOG}" ]; then
  printf '%s\n' "${STRAY_LOG}"
  fail "ログの置き場所が増えています。~/Library/Logs/Mulmo Control に揃えてください（Issue #4）"
fi
ok "ログの置き場所は1つだけ"

# MulmoTerminal を起こす前に、既に誰かが同じポートで応答していないか見る。
# 見ないと MulmoTerminal は "Port is already in use" で exit 1 し、plist の
# KeepAlive がそれを異常終了とみなして約10秒ごとに蘇生し続ける。起動に失敗する
# プロセスもワークスペースを書き換えるので、その先の画面がリロードを繰り返す
# ところまで壊れる。消しても作者の環境では一度も二重にならないと気づけない。
if ! grep -vE '^[[:space:]]*#' "${ROOT}/scripts/start-mulmoterminal.sh" \
  | grep -q 'curl.*"http://\${MULMO_AGENT_HOST}:\${PORT}/"'; then
  fail "起動前のポート確認がありません。二重起動すると KeepAlive が蘇生し続けます"
fi
ok "起動前に二重起動を避けている"

# ── 空白と ' を含むパス ─────────────────────────────────────────
# SECURITY.md の A 節（001〜007）と B 節（011〜014・018）、F 節（052・053）。
#
# ここだけは静的な grep ではなく、実際に走らせて確かめる。引用符が効いて
# いるかは、動かさないと分からない。#32 は `/Applications/Mulmo Control.app`
# の空白で実際に壊れており、作者の環境では両方とも「正しく見えていた」。
#
# 偽の HOME を作り、その中だけで走らせる。本物の LaunchAgent もログも
# 触らない（plist の場所もログの場所も HOME から組み立てられている）。
step "空白と ' を含むパス"

PROBE="$(mktemp -d "${TMPDIR:-/tmp}/mulmo check XXXXXX")"
trap 'rm -rf "${PROBE}"' EXIT
# 空白・アポストロフィ・XML で意味を持つ3文字を全部入れた名前にする。
PROBE_HOME="${PROBE}/home it's & <ok>"
PROBE_MC="${PROBE}/mulmo claude it's & <dir>"
PROBE_CFG="${PROBE_HOME}/Library/Application Support/Mulmo Control"
PROBE_PLIST="${PROBE_HOME}/Library/LaunchAgents/com.mulmocontrol.mulmoterminal.plist"
mkdir -p "${PROBE_HOME}/.local/bin" "${PROBE_MC}" "${PROBE_CFG}"

cfg() { HOME="${PROBE_HOME}" "${ROOT}/scripts/mulmo-config-get" "$1"; }

# 001 設定ファイルがまだ無い状態。install.sh を通す前がこれ。
[ -z "$(cfg MULMO_CONTROL_BRANCH)" ] || fail "設定ファイルが無いのに値を返しました（001）"
# 002 空のファイルで落ちない。
: > "${PROBE_CFG}/app-info.env"
[ -z "$(cfg MULMO_CONTROL_BRANCH)" ] || fail "空の設定ファイルで値を返しました（002）"

# 003〜007 許可したキーだけを、値をそのまま読む。
{
  echo "MULMO_CONTROL_REPO_URL=https://example.com/x.git"
  echo "MULMO_CONTROL_SOURCE_DIR=${PROBE_HOME}/src"
  echo "MULMO_CONTROL_BRANCH=main"
  printf 'MULMO_CONTROL_MULMOCLAUDE_DIR=%s\n' "${PROBE_MC}"
  echo "MULMO_CONTROL_UNKNOWN_KEY=見えてはいけない"
} > "${PROBE_CFG}/app-info.env"
[ "$(cfg MULMO_CONTROL_REPO_URL)" = "https://example.com/x.git" ] || fail "REPO_URL を読めません（003）"
[ "$(cfg MULMO_CONTROL_SOURCE_DIR)" = "${PROBE_HOME}/src" ] || fail "SOURCE_DIR を読めません（004）"
[ "$(cfg MULMO_CONTROL_BRANCH)" = "main" ] || fail "BRANCH を読めません（005）"
# 012 値にアポストロフィと空白が入っていても、1文字も欠けずに返る。
[ "$(cfg MULMO_CONTROL_MULMOCLAUDE_DIR)" = "${PROBE_MC}" ] || fail "' や空白を含む値が壊れます（006/012）"
[ -z "$(cfg MULMO_CONTROL_UNKNOWN_KEY)" ] || fail "許可していないキーを返しました（007）"
ok "設定は許可したキーだけを、値を欠かさず返す"

# 011/013 起動スクリプトが MulmoClaude の場所を本体へ渡すところ。
# 本物の代わりに、受け取った引数をそのまま書き出すものを置いて中身を見る。
# ここが壊れると、空白の手前で切れた場所を --cwd に渡して起動する。
#
# 注意: zsh は引用符を外しただけでは単語に分かれない（sh と違う）。なので
# 「引用符を外して落ちるか」は、この検査の有効性を測る方法にならない。
# 実際に壊れるのは #32 の形 —— コマンドを1本の文字列に組んで zsh -c に
# 渡すとき。その形に書き換えるとここで落ちることを実測した。
cat > "${PROBE_HOME}/.local/bin/mulmoterminal" <<'FAKE'
#!/bin/zsh
for a in "$@"; do printf '%s\n' "$a"; done
FAKE
chmod +x "${PROBE_HOME}/.local/bin/mulmoterminal"
LAUNCH_OUT="$(HOME="${PROBE_HOME}" MULMOTERMINAL_PORT=39917 \
  "${ROOT}/scripts/start-mulmoterminal.sh" 2>&1 || true)"
if ! printf '%s\n' "${LAUNCH_OUT}" | grep -qx -- '--cwd'; then
  printf '%s\n' "${LAUNCH_OUT}"
  fail "起動スクリプトが --cwd を渡していません（011/013）。ポート 39917 が塞がっている場合も出ます"
fi
PASSED_CWD="$(printf '%s\n' "${LAUNCH_OUT}" | awk 'p { print; exit } /^--cwd$/ { p = 1 }')"
[ "${PASSED_CWD}" = "${PROBE_MC}" ] ||
  fail "起動スクリプトが渡す場所が壊れています（011/013）: ${PASSED_CWD}"
ok "起動スクリプトは空白入りの場所を切らずに渡す"

# 014/018/052 plist に同じ値を埋める側。& < > は XML で意味を持つので、
# 逃がし損ねると plutil が読めないファイルになる。
HOME="${PROBE_HOME}" MULMOTERMINAL_LEGACY_LABELS="mulmo.check.no-such-label" \
  "${ROOT}/scripts/mulmoterminal-install-agent" >/dev/null
/usr/bin/plutil -lint "${PROBE_PLIST}" >/dev/null || fail "生成した plist が壊れています（052）"
PLIST_WD="$(/usr/bin/plutil -extract WorkingDirectory raw -o - "${PROBE_PLIST}")"
[ "${PLIST_WD}" = "${PROBE_MC}" ] || fail "plist の値が往復しません（014/018）: ${PLIST_WD}"
ok "plist は & < > ' を含む場所を往復できる"

# 053 MulmoClaude を入れていない人もいる。実在しない場所を
# WorkingDirectory に書くと、LaunchAgent は起動そのものに失敗する。
rm -rf "${PROBE_MC}"
HOME="${PROBE_HOME}" MULMOTERMINAL_LEGACY_LABELS="mulmo.check.no-such-label" \
  "${ROOT}/scripts/mulmoterminal-install-agent" >/dev/null
PLIST_WD="$(/usr/bin/plutil -extract WorkingDirectory raw -o - "${PROBE_PLIST}")"
[ "${PLIST_WD}" = "${PROBE_HOME}" ] || fail "場所が無いときに HOME へ逃がしていません（053）: ${PLIST_WD}"
ok "場所が無いときは HOME に逃がす"

rm -rf "${PROBE}"
trap - EXIT

# ── MulmoClaude の更新 ──────────────────────────────────────────
# SECURITY.md の G 節。使い捨ての git リポジトリを作って、更新スクリプトを
# 本当に走らせる。
#
# これは長い間できなかった。更新は途中で mulmoclaude-stop を呼ぶが、以前の
# stop は 5173/3001 を持つプロセスを確かめずに落としていたので、検査を回すと
# 動いている本物の MulmoClaude が死んだ（Issue #91）。作業ディレクトリで
# 自分のものだけを選ぶようにしたので、いまは巻き添えが出ない。
#
# 逆に言うと、#91 が戻るとここが本物を落とす。上の「他人のプロセスを
# 巻き添えにしない」ガードは、この検査の前提でもある。
step "MulmoClaude の更新"

SBX="$(mktemp -d "${TMPDIR:-/tmp}/mulmo sandbox XXXXXX")"
trap 'rm -rf "${SBX}"' EXIT
SBX_HOME="${SBX}/home"
SBX_WORK="${SBX}/work"
SBX_REASONS="${SBX_HOME}/Library/Logs/Mulmo Control/mulmo-update-reasons.txt"
mkdir -p "${SBX_HOME}/Library/Application Support/Mulmo Control"

# git の名前は環境に頼らない。CI では未設定でコミットが作れない。
sbx_git() { /usr/bin/git -c user.name=check -c user.email=check@example.com "$@"; }

/usr/bin/git init -q --bare "${SBX}/origin.git"
/usr/bin/git clone -q "${SBX}/origin.git" "${SBX_WORK}" 2>/dev/null
printf '{"name":"sbx","version":"1.0.0","private":true}\n' > "${SBX_WORK}/package.json"
printf 'first\n' > "${SBX_WORK}/CLAUDE.md"
sbx_git -C "${SBX_WORK}" add -A
sbx_git -C "${SBX_WORK}" commit -qm init
sbx_git -C "${SBX_WORK}" branch -M main
sbx_git -C "${SBX_WORK}" push -q origin main
printf 'MULMO_CONTROL_MULMOCLAUDE_DIR=%s\n' "${SBX_WORK}" \
  > "${SBX_HOME}/Library/Application Support/Mulmo Control/app-info.env"

# 068 何も落ちてこなかったなら、そう言う。黙っていると「更新できませんでした」
# だけが残り、壊れているのか元から最新なのか区別が付かない。
HOME="${SBX_HOME}" "${ROOT}/scripts/mulmoclaude-update-latest" >/dev/null 2>&1 || true
grep -q 'すでに最新でした' "${SBX_REASONS}" 2>/dev/null ||
  fail "変化が無いときに理由を残していません（068）"
ok "変化が無いときは「すでに最新」と言う"

# 更新スクリプトを、失敗の理由を変えて何度も走らせる。壊れる順に並べてあり、
# 作業ツリーを壊す 063 / #66 は最後に置いている。
sbx_update() {
  set +e
  HOME="${SBX_HOME}" "${ROOT}/scripts/mulmoclaude-update-latest" >/dev/null 2>&1
  SBX_RC=$?
  set -e
}
sbx_point_at() {
  printf 'MULMO_CONTROL_MULMOCLAUDE_DIR=%s\n' "$1" \
    > "${SBX_HOME}/Library/Application Support/Mulmo Control/app-info.env"
}

# 065 別のブランチを見ていると、git pull は「そのブランチとして」成功する。
# 失敗しないので誰も気づかないまま、本体の更新だけが永遠に届かない（Issue #46）。
# ターミナルを開かせないのがこのアプリの役目なので、こちらで戻す。
sbx_git -C "${SBX_WORK}" remote set-head origin main >/dev/null 2>&1 || true
sbx_git -C "${SBX_WORK}" checkout -q -b feature
sbx_update
[ "$(sbx_git -C "${SBX_WORK}" rev-parse --abbrev-ref HEAD)" = "main" ] ||
  fail "別のブランチから既定のブランチに戻していません（065）"
grep -q 'feature を見ていたので main に戻して更新しました' "${SBX_REASONS}" 2>/dev/null ||
  fail "ブランチを戻したことを理由に残していません（065）"
ok "別のブランチを見ていたら既定のブランチに戻す"

# 067 pull に失敗したら、退避したものを戻してから止める。戻さずに抜けると
# 利用者の変更が stash の中に取り残され、画面には何も出ない。
printf 'dirty\n' >> "${SBX_WORK}/CLAUDE.md"
mv "${SBX}/origin.git" "${SBX}/origin.gone"
sbx_update
mv "${SBX}/origin.gone" "${SBX}/origin.git"
[ "${SBX_RC}" != "0" ] || fail "pull に失敗したのに成功として終わりました（067）"
[ -z "$(sbx_git -C "${SBX_WORK}" stash list)" ] ||
  fail "pull に失敗したあと、退避したものが stash に残っています（067）"
[ -n "$(sbx_git -C "${SBX_WORK}" status --porcelain)" ] ||
  fail "pull に失敗したあと、退避したものが戻っていません（067）"
ok "pull に失敗したら退避を戻してから止まる"
sbx_git -C "${SBX_WORK}" checkout -q -- .

# 061 / 062 MulmoClaude を入れていない人、別の場所に置いている人がいる。
# 黙って続けると、どこにも無いものを更新したことにしてしまう。
mkdir -p "${SBX}/notrepo"
sbx_point_at "${SBX}/notrepo"
sbx_update
[ "${SBX_RC}" != "0" ] || fail "git repo でない場所を指しても止まりません（062）"
sbx_point_at "${SBX}/nowhere"
sbx_update
[ "${SBX_RC}" != "0" ] || fail "存在しない場所を指しても止まりません（061）"
ok "場所が無い・git repo でないときは止まる"
sbx_point_at "${SBX_WORK}"

# 063 / #66 使っているだけで CLAUDE.md は書き換わるので、退避はこちらで
# 面倒を見る。上流と同じ行がぶつかると git stash pop は失敗を返しながら
# 作業ツリーにコンフリクトマーカーを書き込んで止まる。
#
# 「戻せなかった」と「中途半端に戻して壊した」は別物で、後者を「戻せません
# でした」とだけ言って先へ進むと、壊れた package.json のまま yarn install と
# 起動まで走り、利用者には Vite のエラー画面と「更新しました」だけが届く
# （Issue #66）。実際に配ってしまった。
/usr/bin/git clone -q "${SBX}/origin.git" "${SBX}/up" 2>/dev/null
printf 'upstream side\n' > "${SBX}/up/CLAUDE.md"
sbx_git -C "${SBX}/up" add -A
sbx_git -C "${SBX}/up" commit -qm upstream
sbx_git -C "${SBX}/up" push -q origin main
printf 'local side\n' > "${SBX_WORK}/CLAUDE.md"

sbx_update
[ "${SBX_RC}" != "0" ] || fail "退避を戻せずに壊れたのに、成功として終わりました（Issue #66）"
UNMERGED="$(/usr/bin/git -C "${SBX_WORK}" diff --name-only --diff-filter=U 2>/dev/null)"
[ -n "${UNMERGED}" ] || fail "コンフリクトを再現できていません（この検査自体が無効）"
grep -q '壊れたまま' "${SBX_REASONS}" 2>/dev/null ||
  fail "壊れたことを画面に出せる形で残していません（Issue #66）"
ok "退避を戻せずに壊れたら、止まって理由を残す"

rm -rf "${SBX}"
trap - EXIT

# ── 画面に出す記録 ──────────────────────────────────────────────
# SECURITY.md の I 節（081〜084）と E 節（042）。
#
# アプリはこれらのファイルを読んで画面を作る。壊れた JSON を書くと、画面は
# 例外ではなく「未確認」に落ちる。つまり**間違いが静かに消える**ので、
# 手元では気づけない。値そのものより、まず形が保てているかを見る。
step "画面に出す記録"

REC="$(mktemp -d "${TMPDIR:-/tmp}/mulmo record XXXXXX")"
trap 'rm -rf "${REC}"' EXIT
REC_LOGS="${REC}/Library/Logs/Mulmo Control"
mkdir -p "${REC}/Library/Application Support/Mulmo Control"

is_json() { /usr/bin/python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null; }

# 042 上流を確かめられないときは unknown と書く。ここで黙ると、画面には
# 前回の値が残り続けて「最新です」と言い張ることになる。
printf 'MULMO_CONTROL_REPO_URL=%s\n' "${REC}/no-such-repo.git" \
  > "${REC}/Library/Application Support/Mulmo Control/app-info.env"
HOME="${REC}" "${ROOT}/scripts/mulmo-control-self-update" check >/dev/null 2>&1 || true
SELF_JSON="${REC_LOGS}/mulmo-control-self-update.json"
[ -f "${SELF_JSON}" ] || fail "self-update の状態ファイルを書いていません（081）"
is_json "${SELF_JSON}" || fail "self-update の状態が JSON として壊れています（081）"
[ "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "${SELF_JSON}")" = "unknown" ] ||
  fail "上流を確かめられないのに unknown と書いていません（042）"
ok "上流を確かめられないときは unknown と書く"

# 082 更新の一覧。node や npm が無い環境でも、形は保つ。
HOME="${REC}" "${ROOT}/scripts/mulmo-check-updates" >/dev/null 2>&1 || true
UPD_JSON="${REC_LOGS}/mulmo-updates.json"
[ -f "${UPD_JSON}" ] || fail "更新の一覧を書いていません（082）"
is_json "${UPD_JSON}" || fail "更新の一覧が JSON として壊れています（082）"
/usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for key in ("checkedAt", "summary", "items"):
    if key not in d:
        raise SystemExit(f"{key} がありません")
if not isinstance(d["items"], list):
    raise SystemExit("items が配列ではありません")
' "${UPD_JSON}" || fail "更新の一覧の形が変わっています（082）"
ok "更新の一覧は形を保つ"

# 084 まだ一度も更新していない人には、要約ファイルが無い。無いことを
# 「壊れている」と扱うと、入れた直後の画面が全部おかしくなる。
[ ! -f "${REC_LOGS}/mulmo-control-last-update-summary.txt" ] ||
  fail "更新していないのに要約ファイルができています（084）"
ok "更新していない人には要約ファイルを作らない"

rm -rf "${REC}"
trap - EXIT

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
# どちらで署名されているかを出す（Issue #54）。adhoc でも配れるが、その場合は
# ブラウザで落とした人にだけ警告が出る。見えないまま配らないための表示。
if codesign -dv "${APP}" 2>&1 | grep -q "Signature=adhoc"; then
  ok "署名（adhoc・ブラウザ経由では警告が出ます）"
else
  ok "署名（Developer ID）"
fi

# v1.0.9 はここが抜けていて、ほとんどのボタンが動かない版を配った。
/bin/zsh -c "\"${APP}/Contents/Resources/scripts/mulmoclaude-status\" >/dev/null" \
  || fail "同梱スクリプトを空白入りパスから実行できません（Issue #32）"
ok "空白入りパスからの実行"

# ── npm パッケージ ──────────────────────────────────────────────
step "npm パッケージ"
node --check "${ROOT}/bin/mulmo-control.mjs" || fail "bin/mulmo-control.mjs の構文が壊れています"
ok "bin/mulmo-control.mjs"

# 配らないものを間違って追跡しない。yarn を使う検査を足したときに、
# yarn.lock と node_modules/.yarn-integrity をそのまま commit してしまった
# （`git add -A` の確認漏れ）。このリポジトリは依存を持たないので、
# どちらも要らない。
TRACKED_JUNK="$(cd "${ROOT}" && /usr/bin/git ls-files node_modules yarn.lock 2>/dev/null || true)"
if [ -n "${TRACKED_JUNK}" ]; then
  printf '%s\n' "${TRACKED_JUNK}"
  fail "配らないものを追跡しています。git rm --cached で外してください"
fi
ok "node_modules / yarn.lock を追跡していない"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ROOT}/Info.plist")"
PKG_VERSION="$(node -p "require('${ROOT}/package.json').version")"
[ "${APP_VERSION}" = "${PKG_VERSION}" ] \
  || fail "Info.plist が ${APP_VERSION}、package.json が ${PKG_VERSION} でずれています"
ok "版が揃っている（${APP_VERSION}）"

printf '\n\033[32m✓ 全部通りました\033[0m\n'
