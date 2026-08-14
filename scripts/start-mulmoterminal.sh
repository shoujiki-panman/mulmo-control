#!/bin/zsh
set -eu

export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/mulmo-control-config"

# tmux はロケールが UTF-8 に解決できないクライアントに対して非 UTF-8 の出力経路に
# 切り替わり、マップできない文字を 1 セルにつき `_` 1 個で書き出す
# （receptron/mulmoterminal#1634）。launchd の GUI ドメインはロケール変数を
# 持たない（`launchctl getenv LANG` が空）ため、ここで補わないと自動起動したときだけ
# 日本語が全部 `_` になり、日本語入力も確定できなくなる。Issue #62。
#
# macOS は /etc/zprofile で同じことをしている（LANG が空なら C.UTF-8 を入れる）が、
# あれはログインシェルでしか読まれない。このスクリプトの shebang は #!/bin/zsh で
# -l が付いていないので通らない。ここは、その抜けたぶんを埋めているだけ。
#
# 値も /etc/zprofile に合わせて C.UTF-8 にする。tmux が要るのは「UTF-8 に解決できる
# こと」だけなので ja_JP.UTF-8 でも症状は直るが、そうすると自動起動したセッション
# だけ並び順・日付・メッセージ言語が他と食い違う。バグを直すついでに別の食い違いを
# 作らない。
#
# LC_ALL と LC_CTYPE は LANG より優先されるので、入っているときに LANG を足しても
# 無意味。3つとも無いときだけ入れる ＝ 利用者の明示指定は必ず残る。
# 空文字は「無い」として扱う。ログインシェルが実際の LC_ALL と一緒に空の LANG= を
# export することがあり、-z はそれを拾う。
if [ -z "${LC_ALL:-}" ] && [ -z "${LC_CTYPE:-}" ] && [ -z "${LANG:-}" ]; then
  export LANG="C.UTF-8"
fi

CONFIG="${HOME}/Library/Application Support/Mulmo Control/app-info.env"
configured_mulmoclaude_dir="$(mulmo_control_config_value "MULMO_CONTROL_MULMOCLAUDE_DIR" "${CONFIG}")"
MULMOCLAUDE_DIR="${configured_mulmoclaude_dir:-${HOME}/mulmoclaude}"

export PORT="34567"
export MULMOTERMINAL_HOST="127.0.0.1"
export CLAUDE_CWD="${MULMOCLAUDE_DIR}"
export MULMOTERMINAL_NO_UPDATE_CHECK="1"

# claude / codex は Homebrew や npm global にある場合もあるので PATH から探す
CLAUDE_PATH="$(command -v claude || true)"
if [ -n "${CLAUDE_PATH}" ]; then
  export CLAUDE_BIN="${CLAUDE_PATH}"
fi
CODEX_PATH="$(command -v codex || true)"
if [ -n "${CODEX_PATH}" ]; then
  export CODEX_BIN="${CODEX_PATH}"
fi

mkdir -p "${HOME}/.mulmoterminal/logs"

# 既に誰かが 34567 で応答しているなら、何もせず正常終了する。
# ここで黙って exec すると MulmoTerminal は "Port is already in use" で exit 1 し、
# plist の KeepAlive がそれを異常終了とみなして約10秒ごとに蘇生し続ける。
# 起動に失敗するプロセスも、ポートを掴む前にワークスペースを書き換えるため、
# その先の MulmoClaude の画面がリロードを繰り返すところまで壊れる。
if /usr/bin/curl -sf -m 3 -o /dev/null "http://127.0.0.1:${PORT}/"; then
  echo "MulmoTerminal is already serving on ${PORT}; nothing to do."
  exit 0
fi

exec "${HOME}/.local/bin/mulmoterminal" \
  --cwd "${MULMOCLAUDE_DIR}" \
  --port "34567" \
  --no-open
