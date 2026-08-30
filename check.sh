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
  # shebang で見る道具を選ぶ。zsh で python を読ませると必ず落ちる（実際に落ちた）。
  if head -1 "$f" | grep -q 'python'; then
    /usr/bin/python3 -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$f" \
      || fail "構文が壊れています: $(basename "$f")"
  else
    zsh -n "$f" || fail "構文が壊れています: $(basename "$f")"
  fi
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
  # python には `set -u` が無い。未定義の名前はそもそも例外になる。
  head -1 "$f" | grep -q 'python' && continue
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

# 101 自己更新は、自分の写しをバンドルの外に作ってからそちらへ移って走る
# （install.sh が .app を丸ごと消すので、消えたファイルの続きを読めなくなるため）。
# 写した先には兄弟スクリプトが無いので、使うものは連れて行く必要がある。
#
# 連れて行き漏れは黙って壊れる。cp は `|| true` で握り潰しているし、呼び出し側も
# `2>/dev/null || true` なので、設定が読めないまま既定値で走る。しかも apply の
# 経路でしか起きないので、check を押しているだけでは一生気づけない。
#
# 参照している兄弟スクリプトが、全部 cp の対象になっているかを見る。
SELF_UPDATE="${ROOT}/scripts/mulmo-control-self-update"
SELF_BODY="$(grep -vE '^[[:space:]]*#' "${SELF_UPDATE}")"
SELF_REFS="$(printf '%s\n' "${SELF_BODY}" \
  | grep -oE '\$\{SCRIPT_DIR\}/[A-Za-z0-9_.-]+' | sed 's|.*/||' | sort -u)"
SELF_CARRIED="$(printf '%s\n' "${SELF_BODY}" \
  | grep -E '^[[:space:]]*/bin/cp ' | grep -oE '\$\{SCRIPT_DIR\}/[A-Za-z0-9_.-]+' \
  | sed 's|.*/||' | sort -u)"
for ref in ${(f)SELF_REFS}; do
  printf '%s\n' "${SELF_CARRIED}" | grep -qx "${ref}" \
    || fail "自己更新が ${ref} を使っていますが、写しに連れて行っていません（apply で黙って壊れます）"
done
ok "自己更新は使う兄弟スクリプトを写しに連れて行く"

# 079 一時的な失敗は「1回だけ」再試行する。ループにすると、落ちているレジストリを
# 相手に何度も待たされ、利用者はボタンを押したまま何分も待つことになる。
# 呼び出しは `if attempt; then` の形ちょうど2回（1回目と、待ったあとの2回目）。
NPM_ATTEMPTS="$(grep -cE '^if attempt; then' "${ROOT}/scripts/mulmo-npm-install" || true)"
[ "${NPM_ATTEMPTS}" = "2" ] \
  || fail "npm の再試行が ${NPM_ATTEMPTS} 回です（1回目と再試行の2回であるべき）"
grep -vE '^[[:space:]]*#' "${ROOT}/scripts/mulmo-npm-install" | grep -qE '^[[:space:]]*sleep ' \
  || fail "再試行の前に待っていません（間を置かない再試行は同じ失敗を繰り返すだけ）"
ok "npm の再試行は1回だけ・待ってから"

# 080 npm のキャッシュは /private/tmp 側に置く。`/tmp` は `/private/tmp` への
# symlink なので、綴りが揺れると同じ場所を2つの名前で指すことになり、
# 「消したのに残っている」ように見える。既定値の綴りを固定する。
grep -qE 'CACHE="\$\{MULMO_NPM_CACHE:-/private/tmp/' "${ROOT}/scripts/mulmo-npm-install" \
  || fail "npm キャッシュの既定が /private/tmp 側ではありません"
ok "npm キャッシュは /private/tmp 側"

# 096 出したあと、利用者と同じ経路で取り直して版を確かめる。ここが無いと、
# タグは作れたのに資産の添付に失敗した版を「出せた」と思い込む。
# v1.0.44 で実際に踏んだ（要約の修正が入っていない zip を配った）。
REL="$(grep -vE '^[[:space:]]*#' "${ROOT}/release.sh")"
printf '%s\n' "${REL}" | grep -q 'releases/latest/download' \
  || fail "リリース後に配信物を取り直していません"
printf '%s\n' "${REL}" | grep -q '\[ "${PUBLISHED}" = "${VERSION}" \]' \
  || fail "取り直した配信物の版を確かめていません"
ok "リリース後に配信物を取り直して版を確かめる"

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

# 「入っている」の判定を2箇所に持たない（Issue #107）。
#
# 画面がフォルダの有無だけを見ていた一方、スクリプトは .git を求めていた。
# 空のフォルダを指すと、画面は緑で「インストール済み」、更新は毎回失敗、
# しかも `入手` ボタンが消えて入れ直す導線まで塞がる、という形だった。
# 作者は中身のある repo しか指さないので踏まない。
if ! printf '%s\n' "${SW}" | grep -q 'mcInstalled = FileManager.default.fileExists(atPath: "\\(mulmoClaudeDir)/.git")'; then
  fail "MulmoClaude の在否を .git で見ていません。スクリプトと判定が食い違います（Issue #107）"
fi
ok "「入っている」の判定がスクリプトと揃っている"

# 129 追加ツールを「入れる場所」と「版を読む場所」が同じかどうか。
#
# 入れるのは main.swift、読むのは mulmo-check-updates。片方だけ変えると、
# npm は成功しているのに画面は古い版のまま「更新できませんでした」と言い続ける。
# 押しても直らないので、利用者からは壊れているようにしか見えない。実際に起きた。
#
# 綴りを直接比べる。どちらかに別の場所が増えれば、行数が合わなくなって落ちる。
SWIFT_PREFIX="$(grep -oE '\.local/share/[A-Za-z0-9_-]+' "${ROOT}/Sources/main.swift" | sort -u)"
JS_PREFIX="$(grep -oE '\.local/share/[A-Za-z0-9_-]+' "${ROOT}/scripts/mulmo-check-updates" | sort -u)"
[ -n "${SWIFT_PREFIX}" ] || fail "追加ツールの入れ先が main.swift から消えています（129）"
[ -n "${JS_PREFIX}" ] || fail "追加ツールの読み先が mulmo-check-updates から消えています（129）"
[ "${SWIFT_PREFIX}" = "${JS_PREFIX}" ] \
  || fail "追加ツールの入れ先と読み先が違います（入れ先: ${SWIFT_PREFIX} / 読み先: ${JS_PREFIX}）"
ok "追加ツールの入れ先と読み先が同じ"

# 131 更新一覧に、どのボタンでも更新できない項目を入れない。
#
# 一覧に載ると「更新あり」を点けるが、押せるものが無ければ永久に消えない。
# しかも @mulmobridge/client は「最新版」欄にも「追加ツール」欄にも出ないので、
# 画面のどこにも現れないまま amber を点け続けていた。利用者からは、押すものが
# 無いのに更新ありと言われ続ける状態になる。#129 と同じ「押しても直らない」型。
#
# 更新できるのは mulmoterminal / mulmoclaude と、追加ツール（familyPackages）だけ。
UPDATE_IDS="$(grep -oE '^[[:space:]]+id: "[A-Za-z0-9_-]+"' "${ROOT}/scripts/mulmo-check-updates" \
  | sed 's/.*"\(.*\)"/\1/' | sort -u)"
FAMILY_IDS="$(grep -oE '^[[:space:]]+id: "[A-Za-z0-9_-]+"' "${ROOT}/Sources/main.swift" \
  | sed 's/.*"\(.*\)"/\1/' | sort -u)"
[ -n "${UPDATE_IDS}" ] || fail "更新一覧の項目を読み取れません（131）"
[ -n "${FAMILY_IDS}" ] || fail "追加ツールの一覧を読み取れません（131）"
for uid in ${(f)UPDATE_IDS}; do
  case "${uid}" in mulmoterminal|mulmoclaude) continue ;; esac
  printf '%s\n' "${FAMILY_IDS}" | grep -qx "${uid}" \
    || fail "更新一覧の ${uid} は、どのボタンでも更新できません（「更新あり」が消えなくなります）"
done
ok "更新一覧の項目はすべて更新する手段がある"


# 入っていないものの版を、宣言から作らない（Issue #109）。
#
# `^2.9.1` は範囲であって、入っている版ではない。以前はこれを「入っている版」と
# して返していたので、node_modules の無い人に、入っていないものの版が並び
# 「更新あり: 2件」と出ていた。宣言の下限が npm の最新と一致すれば、逆に
# 「最新」と緑で出る。#102 で yarn が飛ばされた人がちょうどこの状態になる。
UPDCHK="$(grep -vE '^[[:space:]]*(//|#)' "${ROOT}/scripts/mulmo-check-updates")"
if printf '%s\n' "${UPDCHK}" | grep -q 'dependencies?\.\[pkgName\]'; then
  fail "入っていないものの版を package.json の宣言から作っています（Issue #109）"
fi
# missing を数えない要約は、1つも入っていない人にも「すべて最新」と言う。
if ! printf '%s\n' "${UPDCHK}" | grep -q 'missingCount'; then
  fail "要約が未導入を数えていません（Issue #109）"
fi
ok "入っていないものを「最新」と言わない"

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

# 134 古い置き場所からの引き継ぎは、印で守られていること。
#
# ~/Documents を読むと macOS が「"書類" フォルダ内のファイルへのアクセス権を
# 求められています」を出す。引き継ぎは一度で済むのに、守りが無いと毎起動で
# 聞きに行く。Documents を iCloud で同期している人には毎回開くことにもなる。
#
# 印が消えたら落とす。関数の中に UserDefaults の guard があることを見る。
MIGRATION="$(awk '/^private func migrateLegacyLogsIfNeeded/,/^}/' "${ROOT}/Sources/main.swift")"
[ -n "${MIGRATION}" ] || fail "引き継ぎの関数が見つかりません（134）"
printf '%s\n' "${MIGRATION}" | grep -q 'UserDefaults' \
  || fail "古い置き場所の引き継ぎが毎起動で走ります。~/Documents を読むたびに許可を聞かれます（134）"
ok "古い置き場所の引き継ぎは一度きり"

# 136 「前回の更新」に残った失敗は、解消したら解消したと添える。
#
# この記録は更新の瞬間に書かれ、次の更新まで書き換わらない。あとから最新に
# なっても失敗だけが残り、同じ画面の上半分が「すべて最新」なのに下半分が
# 失敗を訴える矛盾になる。実際に起きた（#129 を直したあとの化石）。
#
# 記録を消してはいけない（#104 で理由を残すと決めた場所）。添える側が
# 消えていないかを見る。
SW_REPORT="$(grep -vE '^[[:space:]]*(//|/\*|\*)' "${ROOT}/Sources/main.swift")"
printf '%s\n' "${SW_REPORT}" | grep -q 'LinkedText(text: model.lastUpdateReport)' \
  || fail "「前回の更新」を出す場所が見つかりません（136）"
printf '%s\n' "${SW_REPORT}" | grep -q 'lastUpdateNote' \
  || fail "「前回の更新」に、その後どうなったかを添えていません（解消しても失敗が残ります・136）"
ok "「前回の更新」の失敗は解消したら添える"

# 139 停止中に、起動ボタンが出ること。
#
# 「停止中」と書いてある隣に「開く」しか無く、そこから起動できるとは読めなかった。
# 起動を担う startAction は未インストール枝にしか描かれておらず、isAvailable は
# インストール済みそのものなので、入れた人には永遠に到達しないデッドコードだった。
# openAction も止まっていれば起動してから開くが、それが分かるのは押したあと。
# 押す前に画面から分かる必要がある。
#
# ServicePanel の中で startAction が2箇所（停止中・未インストール）から
# 呼ばれていることを見る。片方に戻ると1になって落ちる。
PANEL="$(awk '/^struct ServicePanel/,/^struct Hairline/' "${ROOT}/Sources/main.swift" \
  | grep -vE '^[[:space:]]*(//|/\*|\*)')"
[ -n "${PANEL}" ] || fail "ServicePanel が見つかりません（139）"
PANEL_STARTS="$(printf '%s\n' "${PANEL}" | grep -c 'action: startAction' || true)"
[ "${PANEL_STARTS}" -ge 2 ] \
  || fail "停止中に起動ボタンが出ません。押せるのが「開く」だけに戻っています（139）"
ok "停止中に起動ボタンが出る"

# 141 起こす MulmoClaude に PORT を引き継がせない。
#
# Mulmo Control が MulmoTerminal のセルから起動されていると PORT=34567 を持つ。
# それが yarn dev まで素通りすると、MulmoClaude のバックエンドは MulmoTerminal
# のポートを奪おうとして5回落ち、concurrently -k が vite を道連れにする。
# その間 5173 だけが数秒立つので生存判定は「動作中」と言い、直ったように見える。
#
# yarn dev を起こす行が PORT を外していることを見る。
YARN_DEV="$(grep -vE '^[[:space:]]*#' "${ROOT}/scripts/mulmoclaude-start" | grep 'nohup' || true)"
[ -n "${YARN_DEV}" ] || fail "mulmoclaude-start が yarn dev を起こす行を見失いました（141）"
printf '%s\n' "${YARN_DEV}" | grep -q 'env -u PORT' \
  || fail "起こす MulmoClaude に PORT が引き継がれます。MulmoTerminal のポートを奪って落ちます（141）"
ok "起こす MulmoClaude に PORT を渡さない"

# 143 配色が、外観に応じた値であること。
#
# 台紙は .ultraThinMaterial で、OS の外観にひとりでについていく。色のほうが
# 決め打ちだと、夜は台紙だけが暗くなり、文字と罫線は明るいとき用の濃さのまま
# 沈む。利用者の写真では「最新版」の版番号が完全に消えていた。
#
# 作者の Mac がライトモードなら、この状態は一度も画面に出ない。だから目で見て
# 気づくことに頼れない。Palette の各行が adaptive( を通っていることを見る。
PALETTE="$(awk '/^enum Palette \{/,/^\}/' "${ROOT}/Sources/main.swift" \
  | grep -vE '^[[:space:]]*(//|/\*|\*)')"
[ -n "${PALETTE}" ] || fail "Palette が見つかりません（143）"
PALETTE_VARS="$(printf '%s\n' "${PALETTE}" | grep -c 'static let' || true)"
PALETTE_ADAPTIVE="$(printf '%s\n' "${PALETTE}" | grep 'static let' | grep -c 'adaptive(' || true)"
[ "${PALETTE_VARS}" -gt 0 ] || fail "Palette に色がありません（143）"
[ "${PALETTE_VARS}" = "${PALETTE_ADAPTIVE}" ] \
  || fail "配色に決め打ちの色が混ざっています。ダークモードで沈みます（${PALETTE_ADAPTIVE}/${PALETTE_VARS}・143）"
ok "配色が外観に応じて変わる"

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

# 上のガードは `Library/Logs/` を含む行しか見ないので、`/tmp` に書くログは
# 素通りしていた。実際、ボタンの作業ログが `/tmp/mulmo-control-action.log`
# に置かれたまま残っていた（Issue #104）。`/tmp` は誰でも書けるので、固定名だと
# 先に同名のリンクを置かれる余地もある。
# npm のキャッシュ（/private/tmp/npm-cache-mulmo-control）はログではないので除く。
TMP_LOG="$(grep -rn '/tmp/[A-Za-z0-9_.-]*\.log' "${ROOT}/Sources/main.swift" "${ROOT}/scripts" \
  "${ROOT}/install.sh" "${ROOT}/bin" 2>/dev/null \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*(#|\/\/)/) print }' || true)"
if [ -n "${TMP_LOG}" ]; then
  printf '%s\n' "${TMP_LOG}"
  fail "/tmp にログを書いています。~/Library/Logs/Mulmo Control に置いてください（Issue #104）"
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

# ── スマホ連携の鍵 ──────────────────────────────────────────────
# SECURITY.md の K 節（109〜112）。Issue #145。
#
# Mulmo Control は「スマホ連携（MulmoClaude）」の session blob を Keychain に
# 預かる。中身は Firebase の refreshToken なので、扱いを間違えると平文で
# ログに残る／アンインストールしても残る、という形になる。
step "スマホ連携の鍵"

MC_RECONNECT="${ROOT}/scripts/mulmoclaude-remote-host-reconnect"
MC_CHECK="${ROOT}/scripts/mulmo-check-remote-host"
# 繋ぎ直す口は2つある。ターミナル側も同じ blob を握るので同じ規則を掛ける
# （#147 — 109 と 112 が MulmoClaude 側にしか掛かっておらず、実際に漏れた）。
MT_RECONNECT="${ROOT}/scripts/mulmo-remote-host-reconnect"

# 109 預かった鍵をログに出さない。
#
# run() はスクリプトの stdout/stderr を丸ごと ~/Library/Logs 配下のファイルへ
# 落とす（`( … ) >"${actionLogPath}" 2>&1`）。つまり **echo した時点でログに
# 平文で残る**。「デバッグに一行足す」で壊れる種類なので、綴りではなく
# 「秘密を持つ変数が出力コマンドに渡っていないか」を見る。
#
# 対象の変数は、blob そのもの（SESSION / MC_SESSION）、blob を含む API の応答
# （STATUS / RAW / MC_RAW）、Bearer トークン（TOKEN / MC_TOKEN）。
SECRET_VARS='SESSION|MC_SESSION|MT_SESSION|STATUS|RAW|MC_RAW|TOKEN|MC_TOKEN'
LEAK="$(grep -rnE '(^|[;&|(]|[[:space:]])(echo|print|printf|tee|cat)([[:space:]]|$)' \
  "${MC_RECONNECT}" "${MC_CHECK}" "${MT_RECONNECT}" 2>/dev/null \
  | grep -E "\\\$\\{?(${SECRET_VARS})\\}?" \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }' || true)"
if [ -n "${LEAK}" ]; then
  printf '%s\n' "${LEAK}"
  fail "預かった鍵/トークンを出力コマンドに渡しています。ログに平文で残ります（Issue #145）"
fi
ok "預かった鍵をログに出していない"

# 110 鍵の置き場所（service / account）の綴りを1箇所だけが持つ。
#
# 書く側・読む側・消す側が別のファイルにある。綴りが食い違うと「預けたのに
# 読めない」形になり、画面は永遠に `設定を開く` のままになる。#129 は入れる
# 場所と読む場所が食い違って実際に起きた。
BARE_SERVICE="$(grep -rn 'mulmo-control-remote-host-' \
  "${ROOT}/scripts" "${ROOT}/uninstall.sh" "${ROOT}/install.sh" 2>/dev/null \
  | grep -v 'scripts/mulmoterminal-agent-env:' || true)"
if [ -n "${BARE_SERVICE}" ]; then
  printf '%s\n' "${BARE_SERVICE}"
  fail "鍵の置き場所を直に書いています。mulmoterminal-agent-env の定義を使ってください（Issue #145 / #129）"
fi
KEYCHAIN_CALLS="$(grep -rnE 'security (add|find|delete)-generic-password' \
  "${ROOT}/scripts" "${ROOT}/uninstall.sh" 2>/dev/null \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }' || true)"
if [ -z "${KEYCHAIN_CALLS}" ]; then
  fail "Keychain を触る箇所が1つもありません。鍵を預かる実装が消えています（Issue #145）"
fi
ok "鍵の置き場所は共有定義だけが持つ"

# 111 期限切れの鍵と、アンインストール時の鍵を捨てる。
#
# 401 は「この blob では利用者を復元できない」の意味。持ち続けると画面は
# 「繋げる」と言い続けて毎回失敗する。アンインストールで残ると、アプリを
# 消したあとの Mac に refreshToken が残る。
# 「捨てる関数がある」だけでは足りない。定義したまま呼ばずにいると、この検査は
# 通るのに控えは残る（実際に、呼び出しだけ消して通してしまった）。**401 の枝の
# 中に**捨てる呼び出しがあることを見る。
for RECONNECT in "${MC_RECONNECT}" "${MT_RECONNECT}"; do
  grep -q 'delete-generic-password' "${RECONNECT}" \
    || fail "$(basename "${RECONNECT}") が期限切れ（401）の鍵を捨てていません（Issue #145 / #154）"
  BRANCH_401="$(awk '/^[[:space:]]*401\)/ { inside = 1 } inside { print } inside && /;;/ { exit }' "${RECONNECT}")"
  printf '%s\n' "${BRANCH_401}" | grep -qE 'forget_stash|delete-generic-password' \
    || fail "$(basename "${RECONNECT}") が 401 の枝で控えを捨てていません。毎回同じ失敗を繰り返します（Issue #145 / #154）"
done
# 預かる先は2つある。片方だけ消すと、アプリを消した Mac にもう片方が残る。
for SERVICE_VAR in MULMO_MC_SESSION_SERVICE MULMO_MT_SESSION_SERVICE; do
  grep -q "delete-generic-password" "${ROOT}/uninstall.sh" \
    && grep -q "\${${SERVICE_VAR}}" "${ROOT}/uninstall.sh" \
    || fail "アンインストールで ${SERVICE_VAR} の鍵を消していません。refreshToken が残ります（Issue #145 / #154）"
done
ok "期限切れとアンインストールで鍵を捨てる（両方）"

# 126 預かる先の名前が2つで分かれている。
#
# 同じ service 名にすると、あとから預けたほうが先の控えを上書きする。
# 画面は両方「繋ぐ」と言い続けるのに、押すと相手の blob を送って 401 になる。
# 気づける形の壊れ方ではない（どちらの行も同じ言葉で失敗する）。
AGENT_ENV="${ROOT}/scripts/mulmoterminal-agent-env"
MC_SERVICE_NAME="$(grep -o 'mulmo-control-remote-host-[a-z]*' "${AGENT_ENV}" | sort -u | head -1)"
SERVICE_COUNT="$(grep -o 'mulmo-control-remote-host-[a-z]*' "${AGENT_ENV}" | sort -u | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
if [ "${SERVICE_COUNT}" -lt 2 ]; then
  fail "預かる先の名前が分かれていません（${MC_SERVICE_NAME}）。後から預けたほうが先を潰します（Issue #154 / 126）"
fi
ok "預かる先の名前は2つで分かれている"

# 112 繋がっているときに reconnect を叩かない。
#
# #23 で実測した: 繋がっている状態で reconnect を叩くと 401 が返る。既存の
# 接続は無傷だが、成功しているのに「期限切れです」と言うことになる。
# 引き返す判定が POST より前にあることを、行番号で見る。
for RECONNECT in "${MC_RECONNECT}" "${MT_RECONNECT}"; do
  GUARD_LINE="$(grep -n "get('status', {}).get('connected')" "${RECONNECT}" | head -1 | cut -d: -f1)"
  POST_LINE="$(grep -n '/api/remote-host/reconnect' "${RECONNECT}" | head -1 | cut -d: -f1)"
  if [ -z "${GUARD_LINE}" ] || [ -z "${POST_LINE}" ] || [ "${GUARD_LINE}" -ge "${POST_LINE}" ]; then
    fail "$(basename "${RECONNECT}") が、繋がっているかを確かめる前に reconnect を叩いています。401 になります（Issue #23 / #145 / #147）"
  fi
done
ok "繋がっているときは reconnect を叩かない（両方）"

# ── 状態と表示の対応 ────────────────────────────────────────────
# SECURITY.md の K 節（115）。Issue #149。
#
# 直近5件の不具合のうち4件が「アプリが世界の状態について嘘をつく」形だった
# （#139 #143 #145 #147）。ここまでの検査は main.swift を **文字列として
# grep しているだけで、一度も動かしていない**。だから嘘が出ても気づけない。
#
# 表示を決める部分だけ Sources/StatusDisplay.swift に分けてあるので、
# そこと検査を swiftc で組んで実際に走らせる。アプリと同じ1本を読む。
step "状態と表示の対応"

STATUS_DISPLAY="${ROOT}/Sources/StatusDisplay.swift"
DISPLAY_TEST="${ROOT}/tests/status-display-test.swift"

# 115 状態の全組み合わせで、出る言葉が対応表と一致する。
[ -f "${STATUS_DISPLAY}" ] || fail "Sources/StatusDisplay.swift がありません（Issue #149）"
[ -f "${DISPLAY_TEST}" ] || fail "tests/status-display-test.swift がありません（Issue #149）"

# 外の世界に触るものが混ざると、検査から動かせなくなる。混ざる前に止める。
IMPURE="$(grep -nE '^[[:space:]]*import[[:space:]]+(SwiftUI|AppKit|UserNotifications)|FileManager|URLSession|Process\(' \
  "${STATUS_DISPLAY}" 2>/dev/null || true)"
if [ -n "${IMPURE}" ]; then
  printf '%s\n' "${IMPURE}"
  fail "StatusDisplay.swift が外の世界に触っています。検査から動かせなくなります（Issue #149）"
fi

DISPLAY_BIN="$(mktemp -d "${TMPDIR:-/tmp}/mulmo-display-XXXXXX")/test"
if ! xcrun swiftc -parse-as-library "${STATUS_DISPLAY}" "${DISPLAY_TEST}" -o "${DISPLAY_BIN}" 2>&1; then
  rm -rf "$(dirname "${DISPLAY_BIN}")"
  fail "状態と表示の検査を組めませんでした（Issue #149）"
fi
# `set -e` があるので、失敗を代入で受けるとメッセージを出す前にここで
# 中断する（以降の検査も全部飛ぶ）。`|| DISPLAY_RC=$?` で受け止める。
DISPLAY_OUT=""
DISPLAY_RC=0
DISPLAY_OUT="$("${DISPLAY_BIN}" 2>&1)" || DISPLAY_RC=$?
rm -rf "$(dirname "${DISPLAY_BIN}")"
if [ "${DISPLAY_RC}" != "0" ]; then
  printf '%s\n' "${DISPLAY_OUT}"
  fail "状態と表示が食い違っています（Issue #149）"
fi
ok "${DISPLAY_OUT}"

# ── 版の比べ方 ──────────────────────────────────────────────────
# SECURITY.md の E 節（041・043〜045）。Issue #67。
#
# 写しが兄弟を連れて行くかは、既に「同梱スクリプトの自己完結」が見ている。
#
# 「更新があります」を出すかどうかは版の比較で決まる。ここを文字列比較で
# 書くと、1.0.9 と 1.0.53 で逆になる（文字列では 1.0.9 が後）。新しい版を
# 入れた人に更新を勧め続ける形になり、押しても直らない。
#
# 呼ぶ側は上流を git ls-remote で読むので、そのままでは網がかけられない。
# 比較だけ mulmo-version-status に切り出してあるので、それを実際に動かす。
step "版の比べ方"

VERSION_STATUS="${ROOT}/scripts/mulmo-version-status"
# 上の step でも同じものを見ているが、そちらの変数に頼らない。step の順番を
# 入れ替えた瞬間に空になる。
SELF_UPDATE="${ROOT}/scripts/mulmo-control-self-update"

[ -x "${VERSION_STATUS}" ] || fail "scripts/mulmo-version-status がありません（Issue #67）"

# 043〜045 入っている版と最新版の全組み合わせ。
# 「入っている版 / 最新版 / 期待」。空は「読めなかった」を表す。
VERSION_CASES='1.0.53|1.0.53|current
1.0.53|1.0.54|update
1.0.54|1.0.53|current
1.0.9|1.0.53|update
1.0.53|1.0.9|current
1.0.9|1.0.10|update
1.2.0|1.10.0|update
||unknown
1.0.53||unknown
|1.0.53|unknown'
VERSION_BAD=0
printf '%s\n' "${VERSION_CASES}" | while IFS='|' read -r INSTALLED LATEST EXPECT; do
  ACTUAL="$("${VERSION_STATUS}" "${INSTALLED}" "${LATEST}" 2>/dev/null || echo "(落ちた)")"
  if [ "${ACTUAL}" != "${EXPECT}" ]; then
    printf '  入っている版=%s 最新=%s: 期待 %s / 実際 %s\n' \
      "${INSTALLED:-（読めない）}" "${LATEST:-（読めない）}" "${EXPECT}" "${ACTUAL}"
    VERSION_BAD=1
  fi
  [ "${VERSION_BAD}" = "0" ] || echo "MISMATCH"
done | tee "${TMPDIR:-/tmp}/mulmo-version-cases.$$" >/dev/null
if grep -q MISMATCH "${TMPDIR:-/tmp}/mulmo-version-cases.$$" 2>/dev/null; then
  grep -v '^MISMATCH$' "${TMPDIR:-/tmp}/mulmo-version-cases.$$"
  rm -f "${TMPDIR:-/tmp}/mulmo-version-cases.$$"
  fail "版の比べ方が期待と違います（Issue #67 / 043〜045）"
fi
rm -f "${TMPDIR:-/tmp}/mulmo-version-cases.$$"
ok "版の比べ方 10 通りすべて一致"

# 041 入っている版は Info.plist から読む。
#
# ソースの HEAD で報告すると、入っていない版を「最新です」と言う（#31）。
grep -q 'defaults read "${APP_PLIST}" CFBundleShortVersionString' "${SELF_UPDATE}" \
  || fail "入っている版を Info.plist から読んでいません（Issue #31 / 041）"
ok "入っている版は Info.plist から読む"

# ── エージェントのスマホ連携 ────────────────────────────────────
# SECURITY.md の L 節（116・120・121・128・129）。Issue #160（もとは #152）。
step "エージェントのスマホ連携"

CLAUDE_REMOTE="${ROOT}/scripts/mulmo-claude-remote"
CODEX_REMOTE="${ROOT}/scripts/mulmo-codex-remote"
URL_SINK="${ROOT}/scripts/mulmo-remote-url-sink"
for AGENT_SCRIPT in "${CLAUDE_REMOTE}" "${CODEX_REMOTE}" "${URL_SINK}"; do
  [ -x "${AGENT_SCRIPT}" ] || fail "$(basename "${AGENT_SCRIPT}") がありません（Issue #160）"
done

# 116 claude の信頼フラグ（hasTrustDialogAccepted）を、こちらから書かない。
#
# ここを立てれば初回の確認を飛ばせるが、**人間の同意を機械が偽造する形**に
# なる。読むのはよい（押す前に「確認が要ります」と伝えるため）。書かない。
TRUST_WRITE="$(grep -rnE 'claude\.json' "${ROOT}/scripts" "${ROOT}/Sources" 2>/dev/null \
  | grep -E '>|tee|dump|open\([^)]*[\"'"'"']w' \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }' || true)"
if [ -n "${TRUST_WRITE}" ]; then
  printf '%s\n' "${TRUST_WRITE}"
  fail "claude の信頼フラグを書こうとしています。同意は人が踏むものです（Issue #160 / 116）"
fi
# 部分一致だと、末尾に1文字足すだけの改名を見逃す（実際に見逃した）。
grep -qE 'hasTrustDialogAccepted["'"'"']' "${CLAUDE_REMOTE}" \
  || fail "信頼済みかを見ていません。押す前に伝えられません（Issue #160 / 116）"
# 信頼を確かめてから起動する。順番が逆だと、信頼していないフォルダで切り離した
# まま確認ダイアログが出て、誰にも見えないまま止まる。コメント行は数えない。
# 確認は2箇所にある（状態を見るときと、立てるとき）。**立てる側**が消えたのを
# 見つけたいので、`do_start` の中にあることまで見る。ファイルのどこかに1つ
# あればよい書き方だと、状態側が残っているだけで通ってしまう（実際に通った）。
START_LINE="$(grep -n '^do_start()' "${CLAUDE_REMOTE}" | head -1 | cut -d: -f1)"
LAUNCH_LINE="$(grep -nE '^[[:space:]]*[^#[:space:]].*nohup /usr/bin/script' "${CLAUDE_REMOTE}" | head -1 | cut -d: -f1)"
TRUST_LINE="$(grep -n 'trusted)" != "yes"' "${CLAUDE_REMOTE}" | cut -d: -f1 \
  | awk -v lo="${START_LINE:-0}" -v hi="${LAUNCH_LINE:-0}" '$1 > lo && $1 < hi { print $1; exit }')"
if [ -z "${START_LINE}" ] || [ -z "${LAUNCH_LINE}" ] || [ -z "${TRUST_LINE}" ]; then
  fail "信頼を確かめる前にセッションを立てています。見えない確認で止まります（Issue #160 / 116）"
fi
ok "claude の信頼フラグは読むだけ・確かめてから立てる"

# 120 セッションの画面出力を保存しない。
#
# --remote-control は PTY 越しに TUI をそのまま吐く。ファイルに落とすと
# **会話が平文でログに残る**。行き先は /dev/null か FIFO のどちらかだけ。
START_FOLDED="$(awk '{ while (sub(/\\$/, "")) { if ((getline nxt) > 0) $0 = $0 nxt; else break } print }' "${CLAUDE_REMOTE}")"
LAUNCH="$(printf '%s\n' "${START_FOLDED}" | grep -E 'nohup /usr/bin/script' || true)"
[ -n "${LAUNCH}" ] || fail "セッションを立てる行が見つかりません（Issue #160 / 120）"
printf '%s\n' "${LAUNCH}" | grep -q '\${TYPESCRIPT}' \
  || fail "画面の行き先を直に書いています。/dev/null か FIFO だけにしてください（Issue #160 / 120）"
grep -q 'TYPESCRIPT="/dev/null"' "${CLAUDE_REMOTE}" \
  || fail "FIFO を作れないときの行き先が /dev/null ではありません（Issue #160 / 120）"
grep -q 'mkfifo' "${CLAUDE_REMOTE}" \
  || fail "画面を FIFO に流していません。ファイルに落ちると会話が平文で残ります（Issue #160 / 120）"
ok "セッションの画面出力は保存しない"

# 128 拾うのは入口の URL だけ。
#
# FIFO を読む側が「拾ったもの以外」を書けば、120 は素通りしたまま会話が
# ファイルに残る。書く口が1つだけで、そこに渡るのが一致した文字列だけである
# ことを見る。
SINK_WRITES="$(grep -nE '^[[:space:]]*[^#[:space:]].*\.write\(' "${URL_SINK}" || true)"
# 数えるのは「書く行の総数」。`url` を書く行があるかだけ見ると、隣にもう1行
# 足された分を見逃す（実際に見逃した）。
WRITE_COUNT="$(printf '%s\n' "${SINK_WRITES}" | grep -c '\.write(' || true)"
URL_WRITES="$(printf '%s\n' "${SINK_WRITES}" | grep -c 'handle.write(url' || true)"
if [ "${WRITE_COUNT}" != "1" ] || [ "${URL_WRITES}" != "1" ]; then
  printf '%s\n' "${SINK_WRITES}"
  fail "URL 以外を書く口があります。会話が平文で残ります（Issue #160 / 128）"
fi
grep -q 'URL = re.compile' "${URL_SINK}" \
  || fail "URL の形を決めていません（Issue #160 / 128）"
grep -q 'buffering=0' "${URL_SINK}" \
  || fail "FIFO を buffering=0 で開いていません。URL がいつまでも取れません（Issue #160 / 128）"
ok "拾うのは入口の URL だけ"

# 121 止めるのは自分が立てたものだけ。
#
# pkill / killall で名前で薙ぐと、同じフォルダで人が手で開いた作業中の
# セッションまで消える。控えた pid のものだけ落とす。
BROAD_KILL="$(grep -nE 'pkill|killall' "${CLAUDE_REMOTE}" "${CODEX_REMOTE}" 2>/dev/null \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }' || true)"
if [ -n "${BROAD_KILL}" ]; then
  printf '%s\n' "${BROAD_KILL}"
  fail "名前でまとめて止めています。人が開いたセッションまで消えます（Issue #160 / 121）"
fi
grep -q 'kill "${PID}"' "${CLAUDE_REMOTE}" \
  || fail "控えた pid で止めていません（Issue #160 / 121）"
ok "止めるのは自分が立てたものだけ"

# 129 ペアリングコードをログに残さない。
#
# 短命だが、これ1つで端末が繋がる。run() はスクリプトの stdout をまるごと
# ~/Library/Logs 配下へ落とすので、echo すれば残る。画面に出すためだけに
# 状態へ入れる。
CODE_LEAK="$(grep -rnE '(^|[;&|(]|[[:space:]])(echo|print|printf|tee|cat)([[:space:]]|$)' "${CODEX_REMOTE}" \
  | grep -E '\$\{?CODE\}?' \
  | awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*#/) print }' || true)"
if [ -n "${CODE_LEAK}" ]; then
  printf '%s\n' "${CODE_LEAK}"
  fail "ペアリングコードを出力コマンドに渡しています。ログに残ります（Issue #160 / 129）"
fi
ok "ペアリングコードはログに残さない"

# 131 行に出す説明を、入る長さで書く。
#
# 行は狭い。押す所が2つある行は特に狭く、長い文は真ん中が「…」に潰れる。
# 潰れると、その行にしか書いていないことが読めなくなる
# （`接続がエラーで…で確認が要ります` を実際に出した。#156 と同じ形）。
#
# 長さは目分量ではなく数えて止める。ここを通る文はすべてスクリプトが書く。
DETAIL_LONG="$(AGENT_SCRIPTS="${CLAUDE_REMOTE} ${CODEX_REMOTE}" /usr/bin/python3 -c '
import os, re, sys
limit = 12
bad = []
for path in os.environ["AGENT_SCRIPTS"].split():
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("#"):
            continue
        for text in re.findall(r"write_status\s+\"[^\"]*\"\s+\"([^\"$]*)\"", line):
            if len(text) > limit:
                bad.append("%s: %s（%d文字）" % (os.path.basename(path), text, len(text)))
        for text in re.findall(r"printf .%s..n. \"([^\"$]*)\" > \"\$\{ERR_FILE\}\"", line):
            if len(text) > limit:
                bad.append("%s: %s（%d文字）" % (os.path.basename(path), text, len(text)))
print("\n".join(bad))
')"
if [ -n "${DETAIL_LONG}" ]; then
  printf '%s\n' "${DETAIL_LONG}"
  fail "行に出す説明が長すぎます。真ん中が潰れて読めなくなります（Issue #162 / 131）"
fi
ok "行に出す説明は、入る長さで書く"

# 132 枠が埋まっているときに、繋ぎに行かない。
#
# リモートはマシン名ごとに1つ。ChatGPT アプリが枠を取っている間にこちらから
# 繋ぐと 409 で弾かれ、**12秒おきに再接続を試み続ける**（実測で1時間に79回）。
# 押せば直ると思わせたまま、裏で無駄を回すことになる。先に見て、引き返す。
grep -q 'another_app_serving' "${CODEX_REMOTE}" \
  || fail "先に繋いでいるアプリを見ていません。409 を回し続けます（Issue #164 / 132）"
GUARD_LINE="$(grep -n '^  if another_app_serving; then' "${CODEX_REMOTE}" | head -1 | cut -d: -f1)"
START_CALL="$(grep -n 'codex remote-control start' "${CODEX_REMOTE}" | head -1 | cut -d: -f1)"
if [ -z "${GUARD_LINE}" ] || [ -z "${START_CALL}" ] || [ "${GUARD_LINE}" -ge "${START_CALL}" ]; then
  fail "枠を確かめる前に繋ぎに行っています。409 を回し続けます（Issue #164 / 132）"
fi
# 弾かれたまま置くのも同じこと。畳む口があることを見る。
grep -q 'codex remote-control stop' "${CODEX_REMOTE}" \
  || fail "弾かれたときにデーモンを畳んでいません（Issue #164 / 132）"
ok "枠が埋まっているときは繋ぎに行かない"


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

# 066 既定のブランチに戻せなかったら、退避したものを戻してから止める。
# 戻る先が消えている状況は、上流でブランチ名が変わったときに実際に起きる。
# 作るのは簡単ではないので、origin/HEAD を存在しない先に向けて作る。
# 065 で作った feature がそのまま残っているので、作り直さずに戻る。
sbx_git -C "${SBX_WORK}" checkout -q feature
printf 'dirty\n' >> "${SBX_WORK}/CLAUDE.md"
printf 'ref: refs/remotes/origin/nosuchbranch\n' > "${SBX_WORK}/.git/refs/remotes/origin/HEAD"
sbx_update
printf 'ref: refs/remotes/origin/main\n' > "${SBX_WORK}/.git/refs/remotes/origin/HEAD"
[ "${SBX_RC}" != "0" ] || fail "戻る先が無いのに成功として終わりました（066）"
[ -z "$(sbx_git -C "${SBX_WORK}" stash list)" ] ||
  fail "ブランチを戻せなかったあと、退避したものが stash に残っています（066）"
ok "既定のブランチに戻せなければ退避を戻してから止まる"
sbx_git -C "${SBX_WORK}" checkout -q -- .
sbx_git -C "${SBX_WORK}" checkout -q main
sbx_git -C "${SBX_WORK}" reset -q --hard origin/main

# 064 退避そのものに失敗したら、その先へ進まない。進むと利用者の変更を
# 巻き込んだまま pull することになる。git が書けない状況を作って確かめる。
printf 'dirty\n' >> "${SBX_WORK}/CLAUDE.md"
chmod -R a-w "${SBX_WORK}/.git/objects"
sbx_update
chmod -R u+w "${SBX_WORK}/.git/objects"
[ "${SBX_RC}" != "0" ] || fail "退避に失敗したのに先へ進みました（064）"
grep -q '退避できなかったので、更新を中止しました' "${SBX_REASONS}" 2>/dev/null ||
  fail "退避に失敗した理由を残していません（064）"
ok "退避に失敗したら、その先へ進まない"
sbx_git -C "${SBX_WORK}" checkout -q -- .

# 069 yarn install に失敗したら理由を残す。ここで黙ると、依存が入っていない
# ままの MulmoClaude が起動して、画面だけが壊れる。
# yarn が無い環境では確かめようがないので、その旨を出して飛ばす。
# 壊れた package.json で yarn が本当に失敗するかは環境による。CI では
# 成功して返ってきた（そのまま検査にすると、通っていないのに通ったことに
# なる）。先に別の場所で1回試して、失敗する環境でだけ本番を走らせる。
#
# 見に行く PATH は、更新スクリプトが自分で固定しているものと同じにする。
# 手元のシェルで yarn が見つかっても、スクリプトからは見えないことがある
# （nvm や volta で入れた場合など）。CI がまさにそれで、こちらの測定だけが
# yarn を見つけて「失敗するはず」と判断していた。
SBX_SCRIPT_PATH="${SBX_HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SBX_YARN_FAILS=0
if PATH="${SBX_SCRIPT_PATH}" command -v yarn >/dev/null 2>&1; then
  mkdir -p "${SBX}/yarnprobe"
  printf '{ this is not json\n' > "${SBX}/yarnprobe/package.json"
  set +e
  (cd "${SBX}/yarnprobe" && PATH="${SBX_SCRIPT_PATH}" yarn install >/dev/null 2>&1)
  [ $? != 0 ] && SBX_YARN_FAILS=1
  set -e
fi

if [ "${SBX_YARN_FAILS}" = "1" ]; then
  printf '{ this is not json\n' > "${SBX_WORK}/package.json"
  sbx_update
  sbx_git -C "${SBX_WORK}" checkout -q -- package.json
  [ "${SBX_RC}" != "0" ] || fail "yarn install に失敗したのに成功として終わりました（069）"
  grep -q 'yarn install に失敗した' "${SBX_REASONS}" 2>/dev/null ||
    fail "yarn install の失敗を理由に残していません（069）"
  ok "yarn install に失敗したら理由を残す"
elif PATH="${SBX_SCRIPT_PATH}" command -v yarn >/dev/null 2>&1; then
  ok "yarn install の失敗は確かめていません（この環境では壊れた package.json でも yarn が成功する）"
else
  # #102 yarn が見えないとき、黙って飛ばして「更新しました」と言わない。
  # 依存が古いままの MulmoClaude が起動して、画面だけが壊れる。
  # この道は yarn の無い環境でしか通れないので、CI が受け持つ。
  sbx_update
  grep -q 'yarn が見つからないので依存の更新を飛ばしました' "${SBX_REASONS}" 2>/dev/null ||
    fail "yarn が無いのに、飛ばしたことを理由に残していません（#102）"
  ok "yarn が無いときは、飛ばしたことを理由に残す"
fi

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

# 083 理由はタブ区切りで書く。アプリはこれを分解して画面に並べるので、
# 区切りが崩れると理由が丸ごと出なくなる。ここまでで何行か溜まっている。
/usr/bin/python3 -c '
import sys
lines = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.strip()]
if not lines:
    raise SystemExit("理由が1行も書かれていません")
for l in lines:
    parts = l.split("\t")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        raise SystemExit(f"タブ区切りになっていません: {l!r}")
' "${SBX_REASONS}" || fail "更新の理由がタブ区切りで読めません（083）"
ok "更新の理由はタブ区切りで読める"

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

# 入っていないものの版を、宣言から作らない（Issue #109）。
#
# `^2.9.1` は範囲であって入っている版ではない。以前は node_modules に無いとき
# これを「入っている版」として返していたので、1つも入っていない人に版が並び、
# 「すべて最新」と出ていた。#102 で yarn が飛ばされた人がまさにこの状態になる。
mkdir -p "${REC}/norepo"
printf '{"name":"fake","version":"0.0.1","dependencies":{"mulmocast":"^2.9.1"}}\n' \
  > "${REC}/norepo/package.json"
printf 'MULMO_CONTROL_MULMOCLAUDE_DIR=%s\n' "${REC}/norepo" \
  > "${REC}/Library/Application Support/Mulmo Control/app-info.env"
HOME="${REC}" "${ROOT}/scripts/mulmo-check-updates" >/dev/null 2>&1 || true
/usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
item = next((i for i in d["items"] if i["id"] == "mulmocast"), None)
if item is None:
    raise SystemExit("mulmocast の行がありません")
if item["current"] != "unknown" or item["status"] != "missing":
    raise SystemExit(f"入れていないのに版を報告しています: {item}")
if d["summary"] == "すべて最新":
    raise SystemExit("1つも入っていないのに「すべて最新」と言っています")
' "${UPD_JSON}" || fail "入っていないものについて、事実でない表示をしています（Issue #109）"
ok "入っていないものは「未導入」と言う"

# 084 まだ一度も更新していない人には、要約ファイルが無い。無いことを
# 「壊れている」と扱うと、入れた直後の画面が全部おかしくなる。
[ ! -f "${REC_LOGS}/mulmo-control-last-update-summary.txt" ] ||
  fail "更新していないのに要約ファイルができています（084）"
ok "更新していない人には要約ファイルを作らない"

# 071 node を入れていない人がいる。更新の確認は node に依存しているので、
# そこで黙って落ちると画面は前回の値のまま「最新です」と言い続ける。
#
# スクリプトは PATH を自分で持っているため、外から node を隠せない。写しを作って
# PATH の行だけ差し替える。兄弟スクリプトも要るので scripts ごと写す。
cp -R "${ROOT}/scripts" "${REC}/scripts"
mkdir -p "${REC}/nonode"
for c in mkdir date sed grep tr cat awk; do
  src="$(command -v "${c}" 2>/dev/null || true)"
  [ -n "${src}" ] && ln -sf "${src}" "${REC}/nonode/${c}"
done
/usr/bin/sed 's|^PATH=.*|PATH="'"${REC}"'/nonode:/usr/bin:/bin"|' \
  "${ROOT}/scripts/mulmo-check-updates" > "${REC}/scripts/mulmo-check-updates"
chmod +x "${REC}/scripts/mulmo-check-updates"
HOME="${REC}" "${REC}/scripts/mulmo-check-updates" >/dev/null 2>&1 || true
is_json "${UPD_JSON}" || fail "node が無いときに壊れた JSON を書いています（071）"
[ "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["summary"])' "${UPD_JSON}")" = "Node未検出" ] ||
  fail "node が無いのに、そう言っていません（071）"
ok "node が無いときは「Node未検出」と言う"

# 072 / 077 / 078 画面のいちばん上に出る一行（summary）は npm の返事で変わる。
# ここを間違えると、更新があるのに「すべて最新」と読める。npm を差し替えて
# 返事を決め打ちにし、3通りの分かれ方を実際に踏む。
#
# node は実体なので、要るものだけを並べた置き場所に symlink で連れてくる。
# その置き場所に npm を置くか置かないかで、npm が無い経路も踏める。
NODE_BIN="$(command -v node 2>/dev/null || true)"
[ -n "${NODE_BIN}" ] || fail "node が見つかりません（072/077/078 の検査に要ります）"

mkdir -p "${REC}/mc"
printf '{"name":"mulmoclaude","version":"1.0.0"}\n' > "${REC}/mc/package.json"
printf 'MULMO_CONTROL_MULMOCLAUDE_DIR=%s\n' "${REC}/mc" \
  > "${REC}/Library/Application Support/Mulmo Control/app-info.env"

NPMLESS="${REC}/npmless"
mkdir -p "${NPMLESS}"
for c in mkdir date sed grep tr cat awk; do
  src="$(command -v "${c}" 2>/dev/null || true)"
  [ -n "${src}" ] && ln -sf "${src}" "${NPMLESS}/${c}"
done
ln -sf "${NODE_BIN}" "${NPMLESS}/node"

# PATH をその置き場所に差し替えた写しで走らせる。スクリプトは PATH を自分で
# 持っているので、外から環境変数で渡しても効かない（071 と同じ理由）。
run_updates_with() {   # $1 = PATH の先頭に置く場所
  /usr/bin/sed 's|^PATH=.*|PATH="'"$1"':/usr/bin:/bin"|' \
    "${ROOT}/scripts/mulmo-check-updates" > "${REC}/scripts/mulmo-check-updates"
  chmod +x "${REC}/scripts/mulmo-check-updates"
  HOME="${REC}" "${REC}/scripts/mulmo-check-updates" >/dev/null 2>&1 || true
}
updates_summary() {
  /usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["summary"])' "${UPD_JSON}"
}

# 072 npm が無ければ、最新版は分からない。分からないものを分かったことにすると、
# 古い版のまま「最新です」と出る。
run_updates_with "${NPMLESS}"
/usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
bad = [i["id"] for i in d["items"] if i.get("latest") != "unknown"]
if bad:
    raise SystemExit("npm が無いのに最新版を報告しています: " + ", ".join(bad))
' "${UPD_JSON}" || fail "npm が無いときに最新版を unknown にしていません（072）"
ok "npm が無いときは最新版を unknown と言う"

# 077 npm はあるが答えが返らないとき。入っている版は分かるのに最新が分からない
# ので「一部未確認」。ここで「すべて最新」に倒すと、確かめていないことを
# 確かめたことにしてしまう。
NPMSILENT="${REC}/npmsilent"
cp -R "${NPMLESS}" "${NPMSILENT}"
printf '#!/bin/sh\nexit 1\n' > "${NPMSILENT}/npm"
chmod +x "${NPMSILENT}/npm"
run_updates_with "${NPMSILENT}"
[ "$(updates_summary)" = "一部未確認" ] \
  || fail "確かめられないものがあるのに「$(updates_summary)」と言っています（077）"
ok "確かめられないものがあるときは「一部未確認」と言う"

# 078 更新があるときは件数を出す。「更新あり」だけでは、1つなのか全部なのかが
# 分からない。数字が items の実際の数と合っていることまで見る。
NPMNEWER="${REC}/npmnewer"
cp -R "${NPMLESS}" "${NPMNEWER}"
printf '#!/bin/sh\n[ "$1" = "view" ] && echo 9.9.9\nexit 0\n' > "${NPMNEWER}/npm"
chmod +x "${NPMNEWER}/npm"
run_updates_with "${NPMNEWER}"
/usr/bin/python3 -c '
import json, sys, re
d = json.load(open(sys.argv[1]))
n = len([i for i in d["items"] if i.get("status") == "update"])
if n == 0:
    raise SystemExit("更新があるはずの環境で update が0件です（検査の前提が崩れています）")
summary = d["summary"]
m = re.fullmatch(r"更新あり: (\d+)件", summary)
if not m:
    raise SystemExit("件数を出していません: " + summary)
if int(m.group(1)) != n:
    raise SystemExit("件数が合いません: 表示 " + m.group(1) + " / 実際 " + str(n))
' "${UPD_JSON}" || fail "更新があるときに件数を正しく出していません（078）"
ok "更新があるときは件数を出す"

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
#
# Developer ID で署名できているときは hardened runtime も要る。欠けていても
# codesign は通り、notarytool も受け付けるが、審査が Invalid で返る。release.sh は
# zip を作って提出したあとにそこまで進んでから落ちるので、手前で止める。
# secure timestamp はここで見ない。build-app.sh の --timestamp が失敗すると
# codesign 自体が落ちるので、ここに来た時点で付いている。
CODESIGN_INFO="$(codesign -dv "${APP}" 2>&1)"
if printf '%s\n' "${CODESIGN_INFO}" | grep -q "Signature=adhoc"; then
  ok "署名（adhoc・ブラウザ経由では警告が出ます）"
elif printf '%s\n' "${CODESIGN_INFO}" | grep -q "flags=.*runtime"; then
  ok "署名（Developer ID・hardened runtime）"
else
  fail "Developer ID 署名に hardened runtime がありません（公証が Invalid で返ります）"
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
