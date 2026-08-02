#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Mulmo Control.app"
BUILD_DIR="${ROOT}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}"

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${BUILD_DIR}/module-cache" "${BUILD_DIR}/tmp"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache" \
TMPDIR="${BUILD_DIR}/tmp" \
xcrun swiftc \
  -parse-as-library \
  -sdk "${SDK}" \
  -framework SwiftUI \
  -framework AppKit \
  -framework UserNotifications \
  -module-cache-path "${BUILD_DIR}/module-cache" \
  "${ROOT}/Sources/main.swift" \
  -o "${APP_DIR}/Contents/MacOS/MulmoControl"

cp "${ROOT}/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${ROOT}/Assets/MulmoControl.icns" "${APP_DIR}/Contents/Resources/MulmoControl.icns"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"
chmod +x "${APP_DIR}/Contents/MacOS/MulmoControl"
xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"

echo "${APP_DIR}"
