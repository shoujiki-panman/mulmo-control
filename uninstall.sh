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

# 預かった「スマホ連携（MulmoClaude）の鍵」を Keychain から消す（Issue #145）。
# Firebase の refreshToken を含むので、アプリを消したあとに残しておかない。
# 綴りは共有定義（scripts/mulmoterminal-agent-env）が持っている。
/usr/bin/security delete-generic-password \
  -s "${MULMO_MC_SESSION_SERVICE}" -a "${MULMO_MC_SESSION_ACCOUNT}" >/dev/null 2>&1 || true

echo "Removed Mulmo Control app and LaunchAgent."
echo "Removed the stored remote-host key for MulmoClaude from the keychain."
echo "Logs and MulmoTerminal data were kept under ~/.mulmoterminal."
