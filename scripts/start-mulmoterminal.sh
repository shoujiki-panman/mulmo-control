#!/bin/zsh
set -eu

export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PORT="34567"
export MULMOTERMINAL_HOST="127.0.0.1"
export CLAUDE_CWD="${HOME}/mulmoclaude"
export CLAUDE_BIN="${HOME}/.local/bin/claude"
export CODEX_BIN="${HOME}/.local/bin/codex"
export MULMOTERMINAL_NO_UPDATE_CHECK="1"

mkdir -p "${HOME}/.mulmoterminal/logs"

exec "${HOME}/.local/bin/mulmoterminal" \
  --cwd "${HOME}/mulmoclaude" \
  --port "34567" \
  --no-open
