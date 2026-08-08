#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${HOME}/Documents/Codex/SwiftBarLogs"
LOCAL_BIN="${HOME}/.local/bin"
APP_SUPPORT="${HOME}/Library/Application Support/Mulmo Control"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LABEL="com.shutanuma.mulmoterminal"
PLIST="${LAUNCH_AGENT_DIR}/${LABEL}.plist"
REPO_URL="$(git -C "${ROOT}" config --get remote.origin.url 2>/dev/null || echo "https://github.com/shoujiki-panman/mulmo-control.git")"
COMMIT="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo "unknown")"
MULMOCLAUDE_DIR="${MULMOCLAUDE_DIR:-${HOME}/mulmoclaude}"

# 前提チェック: LaunchAgent を仕込む前に、足りないものがあればここで止める
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "${OS_MAJOR}" -lt 14 ]; then
  echo "この macOS ($(sw_vers -productVersion)) では動きません。macOS 14 (Sonoma) 以降が必要です。" >&2
  exit 1
fi

NPM="$(command -v npm || true)"
if [ -z "${NPM}" ]; then
  echo "npm が見つかりません。先に Node.js を入れてください。" >&2
  exit 1
fi

# MulmoClaude が無くても Mulmo Control は入る。アプリ側に「未インストール」表示と
# 「入手」ボタンの導線があるので、ここで止めるとそこへ辿り着けない。
# LaunchAgent の作業ディレクトリだけは実在する場所が要るので $HOME に逃がす。
WORK_DIR="${MULMOCLAUDE_DIR}"
if [ ! -d "${MULMOCLAUDE_DIR}" ]; then
  WORK_DIR="${HOME}"
  echo "MulmoClaude が ${MULMOCLAUDE_DIR} に見つかりません。このまま続けます。" >&2
  echo "MulmoTerminal だけなら、このままで使えます。" >&2
  echo "MulmoClaude も使う場合は、次で入れてから ./install.sh をやり直してください:" >&2
  echo "  git clone https://github.com/receptron/mulmoclaude.git ~/mulmoclaude" >&2
  echo "既に別の場所にある場合は、その場所を渡してください:" >&2
  echo "  MULMOCLAUDE_DIR=/path/to/mulmoclaude ./install.sh" >&2
fi

CLAUDE_BIN="$(command -v claude || echo "${LOCAL_BIN}/claude")"
CODEX_BIN="$(command -v codex || echo "${LOCAL_BIN}/codex")"

mkdir -p "${LOG_DIR}" "${LOCAL_BIN}" "${APP_SUPPORT}" "${HOME}/.mulmoterminal/logs" "${LAUNCH_AGENT_DIR}"

# アプリの入手: まずビルド済みを GitHub Releases から取る（Xcode 不要）。
# 取れなければ手元でビルドする（Xcode Command Line Tools が要る）。
# MULMO_CONTROL_BUILD=1 で最初からビルドもできる。
ZIP_URL="${MULMO_CONTROL_ZIP_URL:-https://github.com/shoujiki-panman/mulmo-control/releases/latest/download/MulmoControl.zip}"
APP_PATH=""
if [ "${MULMO_CONTROL_BUILD:-0}" != "1" ]; then
  DL_DIR="$(mktemp -d /private/tmp/mulmo-control-dl.XXXXXX)"
  if curl -fsSL --connect-timeout 15 -o "${DL_DIR}/MulmoControl.zip" "${ZIP_URL}"; then
    ditto -x -k "${DL_DIR}/MulmoControl.zip" "${DL_DIR}"
    if [ -x "${DL_DIR}/Mulmo Control.app/Contents/MacOS/MulmoControl" ]; then
      APP_PATH="${DL_DIR}/Mulmo Control.app"
      echo "ビルド済みアプリをダウンロードしました"
    fi
  fi
  if [ -z "${APP_PATH}" ]; then
    echo "ビルド済みアプリを取得できなかったので、手元でビルドします"
  fi
fi

if [ -z "${APP_PATH}" ]; then
  if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Swift コンパイラが見つかりません。アプリのビルドに必要です。" >&2
    echo "次を実行して Xcode Command Line Tools を入れてから、やり直してください:" >&2
    echo "  xcode-select --install" >&2
    exit 1
  fi
  APP_PATH="$("${ROOT}/build-app.sh")"
fi

# アプリが使う補助スクリプトは build-app.sh が .app に同梱するので、ここでは
# コピーしない（Issue #11）。外に置いた写しと二重管理になるのを避ける。
# LaunchAgent は .app の外から起動されるため、そちらが呼ぶぶんだけ ~/.local/bin
# に置く。
cp "${ROOT}/scripts"/mulmoterminal-* "${LOCAL_BIN}/"
cp "${ROOT}/scripts/start-mulmoterminal.sh" "${LOCAL_BIN}/start-mulmoterminal.sh"
chmod +x "${LOCAL_BIN}"/mulmoterminal-* "${LOCAL_BIN}/start-mulmoterminal.sh"

if [ ! -x "${LOCAL_BIN}/mulmoterminal" ]; then
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
  <string>${WORK_DIR}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${LOCAL_BIN}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>PORT</key>
    <string>34567</string>
    <key>MULMOTERMINAL_HOST</key>
    <string>127.0.0.1</string>
    <key>CLAUDE_CWD</key>
    <string>${WORK_DIR}</string>
    <key>CLAUDE_BIN</key>
    <string>${CLAUDE_BIN}</string>
    <key>CODEX_BIN</key>
    <string>${CODEX_BIN}</string>
    <key>MULMOTERMINAL_NO_UPDATE_CHECK</key>
    <string>1</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>StandardOutPath</key>
  <string>${HOME}/.mulmoterminal/logs/host.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/.mulmoterminal/logs/host-error.log</string>
</dict>
</plist>
PLIST

plutil -lint "${PLIST}" >/dev/null

rm -rf "/Applications/Mulmo Control.app"
ditto "${APP_PATH}" "/Applications/Mulmo Control.app"
xattr -cr "/Applications/Mulmo Control.app"
codesign --force --deep --sign - "/Applications/Mulmo Control.app"

cat > "${APP_SUPPORT}/app-info.env" <<INFO
MULMO_CONTROL_REPO_URL='${REPO_URL}'
MULMO_CONTROL_SOURCE_DIR='${ROOT}'
MULMO_CONTROL_INSTALLED_COMMIT='${COMMIT}'
MULMO_CONTROL_BRANCH='main'
MULMO_CONTROL_MULMOCLAUDE_DIR='${MULMOCLAUDE_DIR}'
INFO

SELF_STATUS="${LOG_DIR}/mulmo-control-self-update.json"
if [ "${COMMIT}" = "unknown" ]; then
  SELF_STATE="unknown"
  SELF_DETAIL="未確認"
else
  SELF_STATE="current"
  SELF_DETAIL="最新版です"
fi
cat > "${SELF_STATUS}" <<JSON
{
  "checkedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "${SELF_STATE}",
  "installedCommit": "${COMMIT}",
  "latestCommit": "${COMMIT}",
  "detail": "${SELF_DETAIL}"
}
JSON

echo "Installed: /Applications/Mulmo Control.app"

# 案内より先に起動しておく。案内を読んだ時点でアイコンが実際に並んでいる方が探しやすい。
open -a "/Applications/Mulmo Control.app" 2>/dev/null || true

echo ""
echo "このアプリはウィンドウも Dock アイコンも出しません。"
echo "画面いちばん上の帯の右のほう、時計や Wi-Fi の並びにアイコンが増えます。"
echo "形は '>_' です。更新がある時は下向き矢印の丸いアイコンになります。"
echo "（メニューバーの項目が多い Mac やノッチ付きの Mac では、隠れて見えないことがあります）"
echo "起動しているか確認: pgrep -lf MulmoControl"

# ターミナルの出力を読まない人がいるので、同じことをダイアログでも出す。
# アイコンの絵柄を添えるのは、文章で形を説明するより探すのが速いから。
# 端末から手で叩いた時だけ出す。アプリの自己更新はこの install.sh をログに
# リダイレクトして呼ぶので、更新のたびに初回案内が出ることはない。
# 出せない環境（SSH など）でも install は成功扱いのままにする。
if [ -t 1 ]; then
/usr/bin/osascript >/dev/null 2>&1 <<'OSA' || true
display dialog "Mulmo Control をメニューバーに追加しました。

探す場所は、画面のいちばん上の帯の右のほう。
時計や Wi-Fi のアイコンが並んでいるあたりです。

形は >_ です。
更新がある時だけ、下向き矢印の丸いアイコンに変わります。

クリックすると操作画面が開きます。
ウィンドウや Dock アイコンは出ません。

見当たらない時は、メニューバーが混んでいて隠れています。
他のアプリを終了するか、ノッチのない外部ディスプレイで見てください。" with title "Mulmo Control" buttons {"OK"} default button "OK" with icon (POSIX file "/Applications/Mulmo Control.app/Contents/Resources/MulmoControl.icns")
OSA
fi
