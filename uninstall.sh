#!/bin/zsh
set -eu

# ラベルは scripts/mulmoterminal-agent-env が持っている（Issue #7）。
# 5箇所に散らばっていたのを1箇所に寄せたので、ここも読むだけにする。
. "$(cd "$(dirname "$0")" && pwd)/scripts/mulmoterminal-agent-env"
LABEL="${MULMO_AGENT_LABEL}"
DOMAIN="${MULMO_AGENT_DOMAIN}"

if /bin/launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
  /bin/launchctl bootout "${DOMAIN}/${LABEL}" || true
fi

rm -f "${HOME}/Library/LaunchAgents/${LABEL}.plist"
rm -f "${HOME}/.mulmoterminal/keepalive-enabled"
rm -rf "/Applications/Mulmo Control.app"

echo "Removed Mulmo Control app and LaunchAgent."
echo "Logs and MulmoTerminal data were kept under ~/.mulmoterminal."
