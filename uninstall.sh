#!/bin/zsh
set -eu

LABEL="com.shutanuma.mulmoterminal"
DOMAIN="gui/$(id -u)"

if /bin/launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
  /bin/launchctl bootout "${DOMAIN}/${LABEL}" || true
fi

rm -f "${HOME}/Library/LaunchAgents/${LABEL}.plist"
rm -f "${HOME}/.mulmoterminal/keepalive-enabled"
rm -rf "/Applications/Mulmo Control.app"

echo "Removed Mulmo Control app and LaunchAgent."
echo "Logs and MulmoTerminal data were kept under ~/.mulmoterminal."
