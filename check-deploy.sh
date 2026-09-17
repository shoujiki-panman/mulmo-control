#!/bin/zsh
set -eu

# 置き場所と公開範囲の約束（SECURITY.md の O 節、164〜169）。
#
#   ./check-deploy.sh          単独で走らせる（zsh だけで動く。ビルドも macOS も要らない）
#   ./check-deploy.sh --hook   Claude Code の hook から呼ぶ形（落ちたら 2 で返す）
#
# check.sh の中からも呼ばれる。分けてあるのは、check.sh は Swift のビルドと
# codesign が要って macOS でしか走らないのに対し、ここは grep しかしないので
# 編集のたびに回せるから。AI セッションが 1 行足すたびに、その 1 行が
# 「ネットに出す側」へ滑っていないかを見る。
#
# 元にした記事: https://zenn.dev/singularity/articles/vibe-coding-deploy-and-security
# 要点は3行。
#   画面に鍵をかけても、データのドアは別に開いている。
#   出たら困るものは、そもそも外に置かない。
#   クラウドは、下の段で足りないとわかってから。
#
# このアプリは第1段（手元の Mac で動く。公開するものはゼロ）。ここで見るのは
# 「その段に留まっているか」と「段を上げるなら宣言を先に変えたか」。段を上げる
# 判断そのものは人がする。AI に「〇〇できるようにして」と頼むと最短のコードが
# 返ってきて、最短はたいてい外に置く形なので、そこを機械で止める。

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

HOOK=0
[ "${1:-}" = "--hook" ] && HOOK=1

step() { [ "${HOOK}" = 1 ] || printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
ok()   { [ "${HOOK}" = 1 ] || printf '  ✓ %s\n' "$1"; }
fail() {
  printf '\033[31m✗ %s\033[0m\n' "$1" >&2
  # hook のときは 2 で返す。Claude Code は 2 のときだけ stderr を AI に見せる。
  [ "${HOOK}" = 1 ] && exit 2
  exit 1
}

# grep -rn の結果から `file:line:` を落とし、コメント行を捨てる（check.sh と同じ形）。
noncomment() {
  awk '{ body=$0; sub(/^[^:]*:[0-9]+:/,"",body); if (body !~ /^[[:space:]]*(#|\/\/)/) print }'
}

# 見る対象は git が追跡しているテキストだけ。build/ や node_modules/ は見ない。
# 自分自身は外す。探している綴りが、このファイルには必ず書いてあるため（#83 の罠）。
# .icns / .mp4 は grep -I が飛ばす。
TRACKED=()
for f in $(/usr/bin/git ls-files); do
  case "$f" in check-deploy.sh) continue ;; esac
  [ -f "$f" ] && TRACKED+=("$f")
done

step "置き場所と公開範囲"

# ── 164 公開範囲の宣言 ─────────────────────────────────────────
# 記事の1手目は「誰に見せるかを1文で書く」。決めないまま置くと、D のつもりが
# ないのに D になる。宣言は CLAUDE.md に 1 行。A〜D 以外は書けない。
# 2 行あれば片方だけ直して食い違うので、1 行だけを許す。
SCOPE_LINES="$(grep -nE '^公開範囲:' CLAUDE.md 2>/dev/null || true)"
SCOPE_COUNT="$(printf '%s' "${SCOPE_LINES}" | grep -c . || true)"
[ "${SCOPE_COUNT}" = 1 ] \
  || fail "CLAUDE.md に「公開範囲: A」の行が 1 行だけ要ります（いま ${SCOPE_COUNT} 行）"
SCOPE="$(printf '%s\n' "${SCOPE_LINES}" | sed -E 's/^[0-9]+:公開範囲:[[:space:]]*//; s/[[:space:]].*$//')"
case "${SCOPE}" in
  A|B|C|D) ;;
  *) fail "公開範囲は A / B / C / D のどれかで書いてください（いま「${SCOPE}」）" ;;
esac
STAGE_LINES="$(grep -nE '^段:' CLAUDE.md 2>/dev/null || true)"
[ "$(printf '%s' "${STAGE_LINES}" | grep -c . || true)" = 1 ] \
  || fail "CLAUDE.md に「段: 1」の行が 1 行だけ要ります"
STAGE="$(printf '%s\n' "${STAGE_LINES}" | sed -E 's/^[0-9]+:段:[[:space:]]*//; s/[^0-9].*$//')"
case "${STAGE}" in
  1|2|3|4) ;;
  *) fail "段は 1〜4 で書いてください（いま「${STAGE}」）" ;;
esac
ok "公開範囲 ${SCOPE} ・ 第${STAGE}段 と宣言している"

# ── 165 ブラウザ用でない鍵をコードに書かない ─────────────────────
# 名前で探すと自分のコメントに当たるので、鍵そのものの形で探す。どれも
# 「読まれたら他人があなたの請求でそのサービスを使える」種類。
# 鍵はコメントに書いてあっても漏れるので、ここはコメントを捨てない。
SECRET_SHAPES=(
  'sk-(proj-|ant-)?[A-Za-z0-9_-]{20,}'                       # OpenAI / Anthropic
  'AKIA[0-9A-Z]{16}'                                          # AWS access key
  'AIza[0-9A-Za-z_-]{35}'                                     # Google API key
  'gh[pousr]_[A-Za-z0-9]{36,}'                                # GitHub token
  'xox[abpsr]-[0-9A-Za-z-]{10,}'                              # Slack token
  'hooks\.slack\.com/services/T[0-9A-Z]+/B[0-9A-Z]+/[0-9A-Za-z]+'  # Slack webhook
  '[0-9]{8,10}:AA[0-9A-Za-z_-]{33,}'                          # Telegram bot token
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'  # JWT（Supabase の鍵はこの形）
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'                        # 秘密鍵そのもの
)
for pat in "${SECRET_SHAPES[@]}"; do
  HIT="$(grep -rnIE "${pat}" "${TRACKED[@]}" 2>/dev/null || true)"
  if [ -n "${HIT}" ]; then
    printf '%s\n' "${HIT}" | cut -c1-120 >&2
    fail "鍵の形をした文字列が書かれています。鍵は Keychain か .env に置き、コードには書かない"
  fi
done
# 名前が秘密で、右辺が長い定数。`${...}` や `$(...)` は右辺の頭が $ なので当たらない。
NAMED_SECRET='(SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE_KEY|SERVICE_ROLE)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_.-]{24,}'
HIT="$(grep -rnIE "${NAMED_SECRET}" "${TRACKED[@]}" 2>/dev/null | noncomment || true)"
if [ -n "${HIT}" ]; then
  printf '%s\n' "${HIT}" | cut -c1-120 >&2
  fail "秘密の名前に長い定数を代入しています。値は Keychain か .env から読む"
fi
ok "鍵の形をした文字列がない"

# ── 166 ブラウザに配る名前に秘密を入れない ───────────────────────
# VITE_ / NEXT_PUBLIC_ は「ブラウザに出す」という意味の名前。ここに入れたら
# 環境変数でも公開したのと同じ。今このリポジトリに front-end は無いが、
# 増えた瞬間に見たいのでガードだけ先に置く。
PUBLIC_SECRET='(VITE|NEXT_PUBLIC|REACT_APP|NUXT_PUBLIC|PUBLIC)_[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|PRIVATE|SERVICE_ROLE|API_KEY)'
HIT="$(grep -rnIE "${PUBLIC_SECRET}" "${TRACKED[@]}" 2>/dev/null | noncomment || true)"
if [ -n "${HIT}" ]; then
  printf '%s\n' "${HIT}" | cut -c1-120 >&2
  fail "ブラウザに配る名前（VITE_ / NEXT_PUBLIC_ …）に秘密を入れています。サーバー側から読む形にする"
fi
ok "ブラウザに配る名前に秘密がない"

# ── 167 .env を追跡しない ───────────────────────────────────────
# 鍵の置き場所として .env を許す以上、それを commit したら意味がない。
# .gitignore に書いてあることと、実際に追跡していないことの両方を見る。
grep -qE '^\.env(\*|$)' .gitignore || fail ".gitignore に .env がありません"
TRACKED_ENV="$(/usr/bin/git ls-files '.env' '.env.*' '**/.env' '**/.env.*' 2>/dev/null | grep -v '\.example$' || true)"
if [ -n "${TRACKED_ENV}" ]; then
  printf '%s\n' "${TRACKED_ENV}" >&2
  fail ".env を追跡しています。git rm --cached で外してください"
fi
ok ".env を追跡していない"

# ── 168 待ち受けは loopback だけ ───────────────────────────────
# 第2段（社内ネットワークから見える設定）のままノートを持ち出すと、カフェの
# Wi-Fi で隣の人からも見える。第1段に留まる間は 127.0.0.1 だけで待つ。
# AI が出す起動設定は 0.0.0.0 になっていることが多いので、綴りで止める。
BIND_TARGETS=()
for f in "${TRACKED[@]}"; do
  case "$f" in
    Sources/*|scripts/*|bin/*|*.sh|*.plist) BIND_TARGETS+=("$f") ;;
  esac
done
HIT="$(grep -rnIE '0\.0\.0\.0|INADDR_ANY|\[::\]|"::"|--host[= ]+["'"'"']?(0\.0\.0\.0|::)' "${BIND_TARGETS[@]}" 2>/dev/null | noncomment || true)"
if [ -n "${HIT}" ]; then
  printf '%s\n' "${HIT}" | cut -c1-120 >&2
  fail "全インターフェースで待ち受けています。127.0.0.1 だけにする（持ち出した Mac で他人から見える）"
fi
grep -q 'host: .ipv4(.loopback)' Sources/GuideServer.swift \
  || fail "GuideServer が loopback 以外で待とうとしています"
grep -qE '^MULMO_AGENT_HOST="\$\{MULMOTERMINAL_HOST:-127\.0\.0\.1\}"' scripts/mulmoterminal-agent-env \
  || fail "MulmoTerminal の既定の待ち受けが 127.0.0.1 から変わっています"
ok "待ち受けは 127.0.0.1 だけ"

# ── 169 クラウド／BaaS の足場を黙って持ち込まない ─────────────────
# 第4段に上がると、記事の 2〜8 節が全部要る（ルール・境界線・署名付き URL・
# 認証と名簿）。足場のファイルが 1 つ増えた時点でその段に入っているので、
# 宣言より先に足場が増えたら落とす。上げるなら CLAUDE.md の宣言を変え、
# SECURITY.md の O 節に守りの検査を足してから、ここの一覧を直す。
# 禁止する形を並べると綴りの数だけ穴が開くが、足場のファイル名は決まった
# 綴りしかないので、ここは列挙で足りる。
CLOUD_FILES=(
  vercel.json netlify.toml wrangler.toml wrangler.json
  firebase.json .firebaserc firestore.rules storage.rules
  supabase/config.toml fly.toml render.yaml railway.json app.yaml
  Dockerfile docker-compose.yml docker-compose.yaml
)
FOUND=""
for f in "${CLOUD_FILES[@]}"; do
  /usr/bin/git ls-files --error-unmatch "$f" >/dev/null 2>&1 && FOUND="${FOUND} ${f}"
done
CLOUD_DEPS='"(@supabase/[a-z-]+|firebase|firebase-admin|@vercel/[a-z-]+|wrangler|@cloudflare/[a-z-]+|aws-sdk|@aws-sdk/[a-z-]+)"[[:space:]]*:'
DEP_HIT="$(grep -rnIE "${CLOUD_DEPS}" package.json 2>/dev/null || true)"
if [ -n "${FOUND}" ] || [ -n "${DEP_HIT}" ]; then
  [ -z "${FOUND}" ] || printf '  足場:%s\n' "${FOUND}" >&2
  [ -z "${DEP_HIT}" ] || printf '%s\n' "${DEP_HIT}" >&2
  fail "クラウド／BaaS の足場が増えています。先に CLAUDE.md の公開範囲と段を変え、SECURITY.md の O 節に守りを足してから"
fi
if [ "${STAGE}" -ge 4 ] || [ "${SCOPE}" = D ]; then
  # 宣言だけ先に上がった形。守りの検査が無いまま宣言だけ変わると、
  # 「対策した」という記憶だけが残る（記事 3 節の Supabase と同じ形）。
  fail "第4段／公開範囲 D と宣言していますが、その段の守り（RLS・境界線・署名付き URL・名簿）を見る検査がまだありません"
fi
ok "クラウド／BaaS の足場がない（第${STAGE}段に留まっている）"

[ "${HOOK}" = 1 ] || printf '\n\033[32m✓ 置き場所と公開範囲は約束どおり\033[0m\n'
