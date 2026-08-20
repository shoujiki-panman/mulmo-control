# Apple Developer Program の登録手順

目的: 署名と公証（notarization）を通して、**ブラウザからダウンロードしても警告なしで開ける**ようにする。Raycast と同じ体験。

費用: 年 99 米ドル（登録時に円建てで表示される）
所要: 申し込み自体は15分ほど。**審査に数日かかることがある**

---

## なぜ要るのか

いまのアプリは自己署名（adhoc）。中身が改ざんされていないことは示せるが、**誰が作ったかを含まない**ので、Apple は「検証できませんでした」と言う。

隔離マークが付かない経路（`npx`）なら今のままで開ける。ブラウザ経由でも開けるようにするには、これが要る。

| | いま | 登録後 |
|---|---|---|
| `npx mulmo-control` | 開く | 開く |
| ブラウザ + DMG ドラッグ | **警告** | 開く |

---

## 手順

### 1. Apple ID を用意する

普段使っているもので構わない。**二要素認証が有効になっている必要がある**。

https://appleid.apple.com で確認。

### 2. 申し込む

https://developer.apple.com/programs/enroll/

- 個人（Individual）で申し込む。法人（Organization）は D-U-N-S 番号が要るので、個人で足りる
- 氏名は**身分証と一致**していること。ここが違うと審査で止まる
- 支払いはクレジットカード

### 3. 審査を待つ

即日のこともあれば、数日かかることもある。本人確認の連絡が来る場合がある。

- [x] 申し込んだ日: 2026-08-11（注文番号 W1803651682、¥12,980）
- [x] 承認された日: 2026-08-11（同日。「Apple Developer Programへようこそ」と App Store Connect の案内が届いている）

### 4. 承認されたら

- Team ID: **59FNRWS2H8**（個人登録 / 更新日 2027-08-12。https://developer.apple.com/account の
  メンバーシップの詳細で確認、2026-08-18 時点）

証明書そのものは Xcode か `security` コマンドで手元に作る。**秘密鍵は Mac のキーチェーンから出さない**ので、共有する必要はない。

2026-08-18 時点の手元の状態:

- `security find-identity -v -p codesigning` → **0 valid identities**。証明書は未作成
- developer.apple.com の Certificates / Keys も**どちらも空**
- Xcode 16 系（`/Applications/Xcode.app`）と `notarytool` / `stapler` は入っている

つまり残っているのは「証明書を作る」「App-specific password を作る」の2つで、
どちらも本人の手が要る（キーチェーンとパスワード入力）。

---

## 承認後にやること（実装側）

1. **Developer ID Application 証明書を作る** — Xcode の Settings → Accounts、または developer.apple.com から
2. **`build-app.sh` を書き換える** — `--sign -`（自己署名）から Developer ID へ。あわせて hardened runtime（`--options runtime`）を有効にする。公証の必須条件
3. **公証を通す** — `notarytool submit`。App-specific password が要る（appleid.apple.com で発行）
4. **チケットを貼る** — `stapler staple`。これでオフラインでも検証が通る
5. **DMG を作る** — ドラッグ用の窓（背景画像と Applications へのエイリアス）
6. **`release.sh` に組み込む** — zip と DMG の両方を出す

`npx` の経路は残す。ターミナル派向け、および Claude Code と同じ流儀として。

---

## 注意

- **年払い。更新を忘れると証明書が失効し、配布済みのアプリも新規ダウンロード分は警告が出るようになる**（公証済みのものは stapler のチケットがあるので当面は生きるが、証明書失効後の再配布は不可）
- App-specific password は GitHub Actions などに置くならシークレットとして扱う。**リポジトリに書かない**
- 秘密鍵をなくすと証明書を作り直すことになる。キーチェーンのバックアップを取っておく
