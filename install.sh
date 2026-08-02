#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="${HOME}/Documents/Codex/SwiftBarTools"
LOG_DIR="${HOME}/Documents/Codex/SwiftBarLogs"
LOCAL_BIN="${HOME}/.local/bin"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LABEL="com.shutanuma.mulmoterminal"
PLIST="${LAUNCH_AGENT_DIR}/${LABEL}.plist"

mkdir -p "${TOOLS_DIR}" "${LOG_DIR}" "${LOCAL_BIN}" "${HOME}/.mulmoterminal/logs" "${LAUNCH_AGENT_DIR}"

cp "${ROOT}/scripts"/mulmo* "${TOOLS_DIR}/"
cp "${ROOT}/scripts"/open-swiftbar-logs "${TOOLS_DIR}/" 2>/dev/null || true
cp "${ROOT}/scripts"/mulmoterminal-* "${LOCAL_BIN}/"
cp "${ROOT}/scripts/start-mulmoterminal.sh" "${LOCAL_BIN}/start-mulmoterminal.sh"
chmod +x "${TOOLS_DIR}"/* "${LOCAL_BIN}"/mulmoterminal-* "${LOCAL_BIN}/start-mulmoterminal.sh"

if [ ! -x "${LOCAL_BIN}/mulmoterminal" ]; then
  NPM="$(command -v npm || true)"
  if [ -z "${NPM}" ]; then
    echo "npm was not found. Install Node.js first."
    exit 1
  fi
  mkdir -p "${HOME}/.local/share/mulmoterminal" /private/tmp/npm-cache-mulmo-control
  NPM_CONFIG_CACHE="/private/tmp/npm-cache-mulmo-control" "${NPM}" install \
    --prefix "${HOME}/.local/share/mulmoterminal" \
    mulmoterminal@latest
  ln -sf "${HOME}/.local/share/mulmoterminal/node_modules/.bin/mulmoterminal" "${LOCAL_BIN}/mulmoterminal"
fi

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${LOCAL_BIN}/start-mulmoterminal.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${HOME}/mulmoclaude</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${LOCAL_BIN}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>PORT</key>
    <string>34567</string>
    <key>MULMOTERMINAL_HOST</key>
    <string>127.0.0.1</string>
    <key>CLAUDE_CWD</key>
    <string>${HOME}/mulmoclaude</string>
    <key>CLAUDE_BIN</key>
    <string>${LOCAL_BIN}/claude</string>
    <key>CODEX_BIN</key>
    <string>${LOCAL_BIN}/codex</string>
    <key>MULMOTERMINAL_NO_UPDATE_CHECK</key>
    <string>1</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/.mulmoterminal/logs/host.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.mulmoterminal/logs/host-error.log</string>
</dict>
</plist>
PLIST

plutil -lint "${PLIST}" >/dev/null

APP_PATH="$("${ROOT}/build-app.sh")"
rm -rf "/Applications/Mulmo Control.app"
ditto "${APP_PATH}" "/Applications/Mulmo Control.app"
xattr -cr "/Applications/Mulmo Control.app"
codesign --force --deep --sign - "/Applications/Mulmo Control.app"

echo "Installed: /Applications/Mulmo Control.app"
echo "Open it from Finder, or run: open '/Applications/Mulmo Control.app'"
