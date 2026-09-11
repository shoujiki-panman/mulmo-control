#!/bin/zsh
set -eu

# GitHub 側でリリースを出すための準備を、1回だけやる（Issue #198）。
#
#   ./release-setup.sh
#
# 手元の Mac にある Developer ID 証明書を書き出し、公証に使う Apple ID と
# App用パスワードを聞いて、5つを GitHub の Secrets に預ける。以後は Actions の
# 画面で「Run workflow」を押せば、ビルド・署名・公証・公開まで GitHub 側で走る。
#
# 預ける値はこの script の中で表示しない。gh に渡すときも引数ではなく stdin を
# 使う（引数は同じ利用者の ps から見える。#145 で踏んだ）。
#
# 途中で「security が鍵を書き出そうとしています」というダイアログが出たら
# 「許可」を押す。証明書の秘密鍵に触るので、macOS が1回だけ確認してくる。

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '  ✓ %s\n' "$1"; }

step "前提を確認"
command -v gh >/dev/null 2>&1 || fail "gh が要ります（brew install gh）"
gh auth status >/dev/null 2>&1 || fail "gh がログインしていません（gh auth login）"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
  || fail "このフォルダから GitHub のリポジトリが分かりません"
ok "預け先: ${REPO}"

# 証明書は名前ではなく SHA-1 で選ぶ（build-app.sh と同じ）。表示名には氏名が
# 入るので、ここでも表示しない。
IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Developer ID Application' || true)"
[ -n "${IDENTITY_LINE}" ] || fail "Developer ID Application の証明書がキーチェーンにありません"
if [ "$(printf '%s\n' "${IDENTITY_LINE}" | wc -l | tr -d ' ')" != "1" ]; then
  if [ -n "${MULMO_SIGN_IDENTITY:-}" ]; then
    IDENTITY_LINE="$(printf '%s\n' "${IDENTITY_LINE}" | grep "${MULMO_SIGN_IDENTITY}" || true)"
    [ -n "${IDENTITY_LINE}" ] || fail "MULMO_SIGN_IDENTITY に合う証明書がありません"
  else
    fail "Developer ID Application の証明書が複数あります。MULMO_SIGN_IDENTITY=<SHA-1> で選んでください"
  fi
fi
TEAM_ID="$(printf '%s\n' "${IDENTITY_LINE}" | sed -n 's/.*(\([A-Z0-9]\{10\}\))".*/\1/p')"
[ -n "${TEAM_ID}" ] || fail "証明書の表示名から Team ID を読めませんでした"
ok "Developer ID 証明書（Team ID: ${TEAM_ID}）"

# ── 聞くものは2つだけ ──────────────────────────────────────────
step "公証に使う Apple ID"
printf '  公証に使う Apple ID（メールアドレス）: '
read -r APPLE_ID
[ -n "${APPLE_ID}" ] || fail "Apple ID が空です"

printf '  App用パスワード（appleid.apple.com → サインインとセキュリティ → App用パスワード で作る。入力は表示されません）: '
read -rs APP_PASSWORD
printf '\n'
[ -n "${APP_PASSWORD}" ] || fail "App用パスワードが空です"
printf '%s' "${APP_PASSWORD}" | grep -qE '^[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}$' \
  || fail "App用パスワードの形（xxxx-xxxx-xxxx-xxxx）ではありません。Apple ID のパスワードではなく、App用パスワードを作ってください"

# 預ける前に、その組で公証に入れるかを Apple に聞く。ここで落ちれば
# GitHub 側で落ちて初めて気づく、という回り道を省ける。
xcrun notarytool history --apple-id "${APPLE_ID}" --team-id "${TEAM_ID}" --password "${APP_PASSWORD}" >/dev/null 2>&1 \
  || fail "その Apple ID / App用パスワード / Team ID の組で Apple に入れませんでした"
ok "Apple に入れることを確認"

# ── 証明書を書き出す ───────────────────────────────────────────
step "証明書を書き出す"
WORK="$(mktemp -d /private/tmp/mulmo-release-setup.XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT
P12_PASSWORD="$(openssl rand -base64 24)"
# security export は種類でしか選べないので、同じキーチェーンにある署名用の
# 身元が全部入る。GitHub 側は Developer ID Application だけを選んで使う。
security export -t identities -f pkcs12 -P "${P12_PASSWORD}" -o "${WORK}/certificate.p12" >/dev/null \
  || fail "証明書を書き出せませんでした（ダイアログで「許可」を押しましたか）"
[ -s "${WORK}/certificate.p12" ] || fail "書き出した証明書が空です"
ok "書き出した（この Mac のキーチェーンはそのまま）"

# ── 預ける ────────────────────────────────────────────────────
# 名前は .github/workflows/release.yml が読むものと揃える。check.sh が
# 突き合わせているので、片方だけ変えると PR で落ちる。
step "GitHub の Secrets に預ける"
base64 -i "${WORK}/certificate.p12" | tr -d '\n' \
  | gh secret set MACOS_CERTIFICATE_P12 --repo "${REPO}" >/dev/null
ok "MACOS_CERTIFICATE_P12"
printf '%s' "${P12_PASSWORD}" | gh secret set MACOS_CERTIFICATE_PASSWORD --repo "${REPO}" >/dev/null
ok "MACOS_CERTIFICATE_PASSWORD"
printf '%s' "${APPLE_ID}" | gh secret set NOTARY_APPLE_ID --repo "${REPO}" >/dev/null
ok "NOTARY_APPLE_ID"
printf '%s' "${TEAM_ID}" | gh secret set NOTARY_TEAM_ID --repo "${REPO}" >/dev/null
ok "NOTARY_TEAM_ID"
printf '%s' "${APP_PASSWORD}" | gh secret set NOTARY_PASSWORD --repo "${REPO}" >/dev/null
ok "NOTARY_PASSWORD"

printf '\n\033[32m✓ 準備できました\033[0m\n'
printf '  次からのリリースは、ここでバージョンを入れて Run workflow を押すだけです:\n'
printf '  https://github.com/%s/actions/workflows/release.yml\n' "${REPO}"
printf '  やめるときは Apple 側で証明書と App用パスワードを無効にし、Secrets を消してください\n'
