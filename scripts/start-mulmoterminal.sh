#!/bin/zsh
set -eu

export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# tmux はロケールが UTF-8 に解決できないクライアントに対して非 UTF-8 の出力経路に
# 切り替わり、マップできない文字を 1 セルにつき `_` 1 個で書き出す
# （receptron/mulmoterminal#1634）。launchd の GUI ドメインはロケール変数を
# 持たない（`launchctl getenv LANG` が空）ため、ここで補わないと自動起動したときだけ
# 日本語が全部 `_` になり、日本語入力も確定できなくなる。Issue #62。
#
# LC_ALL と LC_CTYPE は LANG より優先されるので、入っているときに LANG を足しても
# 無意味。3つとも無いときだけ入れる ＝ 利用者の明示指定は必ず残る。
# 空文字は「無い」として扱う。ログインシェルが実際の LC_ALL と一緒に空の LANG= を
# export することがあり、-z はそれを拾う。
if [ -z "${LC_ALL:-}" ] && [ -z "${LC_CTYPE:-}" ] && [ -z "${LANG:-}" ]; then
  export LANG="ja_JP.UTF-8"
fi

CONFIG="${HOME}/Library/Application Support/Mulmo Control/app-info.env"
if [ -f "${CONFIG}" ]; then
  . "${CONFIG}"
fi
MULMOCLAUDE_DIR="${MULMO_CONTROL_MULMOCLAUDE_DIR:-${HOME}/mulmoclaude}"

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
