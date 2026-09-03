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
    "${ROOT}/Sources/StatusDisplay.swift" \
    "${ROOT}/Sources/GuideServer.swift" \
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

# 署名（Issue #54）。
#
# Developer ID Application 証明書がキーチェーンにあればそれで署名する。あわせて
# hardened runtime（--options runtime）と secure timestamp（--timestamp）を付ける。
# どちらも公証の必須条件で、欠けていると notarytool が受け付けても Invalid で返る。
#
# 証明書が無ければ従来どおり adhoc（--sign -）で署名する。証明書を作る前でも
# ビルドは通り、check.sh も release.sh も adhoc を通る道を持っている。
#
# 証明書は名前ではなく SHA-1 で指定する。表示名（"Developer ID Application: 氏名
# (TEAMID)"）は氏名を含むので、別の登録者の Mac でも通るようにしてある。
# MULMO_SIGN_IDENTITY で明示指定もできる（証明書が複数あるときはこれで選ぶ）。
SIGN_IDENTITY="${MULMO_SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
  # grep が空振りしても代入は成功する（zsh は pipefail を既定にしない）。
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 | awk '{print $2}')"
fi

# 署名は同期の外でやる（実測 2026-09-03）。
#
# このリポジトリが iCloud Drive 配下にあると、署名の最中に fileprovider が
# `com.apple.fileprovider.fpfs` を付け直し、codesign --verify が
# 「resource fork, Finder information, or similar detritus not allowed」で落ちる。
# 掃除→署名→検証を5回繰り返しても付け直しの方が速く、勝てなかった。
# だから**同期対象外の /tmp に写してから**署名し、署名済みを build/ へ戻す。
# 戻したあとの verify は check.sh がやる（戻し先でまた属性が付くのは
# 署名データ自体を壊さないので、配布物 zip は ditto --norsrc で作れば問題ない）。
STAGE_DIR="$(mktemp -d /tmp/mulmo-control-sign.XXXXXX)"
trap 'rm -rf "${STAGE_DIR}"' EXIT
STAGE_APP="${STAGE_DIR}/${APP_NAME}"
ditto --norsrc --noextattr "${APP_DIR}" "${STAGE_APP}"
sign_at() {
  if [ -n "${SIGN_IDENTITY}" ]; then
    codesign --force --deep --options runtime --timestamp \
      --sign "${SIGN_IDENTITY}" "$1"
  else
    codesign --force --deep --sign - "$1"
  fi
}
sign_at "${STAGE_APP}"
codesign --verify --deep --strict "${STAGE_APP}"
rm -rf "${APP_DIR}"
ditto --norsrc --noextattr "${STAGE_APP}" "${APP_DIR}"

echo "${APP_DIR}"
