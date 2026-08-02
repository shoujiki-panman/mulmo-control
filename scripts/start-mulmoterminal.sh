#!/bin/zsh
set -eu

export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

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

exec "${HOME}/.local/bin/mulmoterminal" \
  --cwd "${MULMOCLAUDE_DIR}" \
  --port "34567" \
  --no-open
