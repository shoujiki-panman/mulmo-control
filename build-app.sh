#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Mulmo Control.app"
BUILD_DIR="${ROOT}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}"

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources" "${BUILD_DIR}/module-cache" "${BUILD_DIR}/tmp"

SDK="$(xcrun --show-sdk-path --sdk macosx)"

# Apple Silicon と Intel の両方で動くよう、2アーキテクチャを別々にビルドして束ねる
for ARCH in arm64 x86_64; do
  CLANG_MODULE_CACHE_PATH="${BUILD_DIR}/module-cache-${ARCH}" \
  TMPDIR="${BUILD_DIR}/tmp" \
  xcrun swiftc \
    -parse-as-library \
    -sdk "${SDK}" \
    -target "${ARCH}-apple-macos14.0" \
    -framework SwiftUI \
    -framework AppKit \
    -framework UserNotifications \
    -module-cache-path "${BUILD_DIR}/module-cache-${ARCH}" \
    "${ROOT}/Sources/main.swift" \
    -o "${BUILD_DIR}/MulmoControl-${ARCH}"
done
lipo -create \
  "${BUILD_DIR}/MulmoControl-arm64" \
  "${BUILD_DIR}/MulmoControl-x86_64" \
  -output "${APP_DIR}/Contents/MacOS/MulmoControl"

cp "${ROOT}/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${ROOT}/Assets/MulmoControl.icns" "${APP_DIR}/Contents/Resources/MulmoControl.icns"

# 補助スクリプトを同梱する。アプリのボタンはここを呼ぶので、外部にコピーされて
# いなくても動く（Issue #11）。zip を Applications にドラッグしただけの状態を
# 成立させるための前提。
rm -rf "${APP_DIR}/Contents/Resources/scripts"
mkdir -p "${APP_DIR}/Contents/Resources/scripts"
cp "${ROOT}/scripts"/* "${APP_DIR}/Contents/Resources/scripts/"
chmod +x "${APP_DIR}/Contents/Resources/scripts"/*
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"
chmod +x "${APP_DIR}/Contents/MacOS/MulmoControl"
xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"

echo "${APP_DIR}"
