# 実機テスト手順 — 素の Mac で使い始められるか（#15）

対象: v1.0.18 以降
所要: 20〜30分

机上で潰せるところは潰してある。ここに残っているのは**人が触らないと分からないこと**だけ。

---

## 先に分かったこと（2026-08-11 実測）

### ブラウザから落とした zip は開けない。右クリックでも駄目

macOS 26.4 で実際にぶつかった。出るのはこれ。

```
"Mulmo Control" は開いていません
Apple は、"Mulmo Control" に Mac に損害を与えたり、プライバシーを
侵害する可能性のあるマルウェアが含まれていないことを検証できませんでした。

  [ゴミ箱に入れる]  [完了]
```

**選択肢に「開く」が無い。** macOS 15 以降、右クリック → 開く の抜け道は塞がれた。以前の資料にある「右クリックで開けます」は**この macOS では通用しない**。

復帰するには `システム設定 → プライバシーとセキュリティ` を開き、下のほうに出る「このまま開く」を押す。（この経路自体はまだ実機で通していない。試したら結果をここに書く）

### 原因は署名ではなく、配り方だった

| 経路 | 隔離マーク | 開けるか |
|---|---|---|
| ブラウザでダウンロード | **付く** | 止められる |
| `curl` でダウンロード | 付かない | **開く** |
| `npm` で取得 | 付かない | **開く** |

Gatekeeper が止めるのは**隔離マークが付いたものだけ**。自己署名（adhoc）かどうかは、隔離マークが無ければ関係ない。現に `/Applications/Mulmo Control.app` は adhoc 署名・隔離なしで動いている。

`install.sh` が今日まで問題なく動いていたのは、curl で落としていたから。

### 方針: npm 配布にする

Claude Code も MulmoTerminal も npm や `curl | bash` で配っていて、ブラウザを経由しないから Gatekeeper に触れない。同じ流儀にする。

対象利用者は MulmoTerminal のために既に Node.js を入れているので、`npx` は追加の負担にならない。**「怖いダイアログを乗り越えてもらう」より親切**という判断。

→ **「zip をドラッグ」の経路は当面ゴールから外す。** 下の手順1〜3は、その決定の裏付けを取るためだけに残してある。

---

## 準備

**別のユーザーアカウントを作るのが一番きれい。** 自分のアカウントには `~/.local/bin` も `~/Documents/Codex/` も既にあるので、素の状態を再現できない。

`システム設定 → ユーザとグループ → ユーザを追加`

作れない場合は退避でも代用できる（テスト後に必ず戻す）。

```bash
mv ~/.local/bin ~/.local/bin.bak
mv ~/Documents/Codex/SwiftBarTools ~/Documents/Codex/SwiftBarTools.bak
```

---

## 手順1〜3: Gatekeeper の確認（済み・記録用）

- [x] ブラウザで zip を落とすと隔離マークが付く
- [x] ダブルクリックでは開けない
- [x] ダイアログに「開く」の選択肢は無い
- [ ] `システム設定 → プライバシーとセキュリティ` から「このまま開く」で開けるか **← 未確認**

やるなら、その1点だけ確かめれば足りる。**npm 配布に移ると使わない経路**なので、優先度は低い。

---

## 手順4〜8: アプリそのものの確認（本命）

隔離マークを避けて入れる。curl 経由なので Gatekeeper に触れない。

```bash
cd ~/mulmoclaude/github/mulmo-control && ./install.sh
```

npm 配布が実装されたら、ここが `npx mulmo-control` に変わる。**確かめる中身は同じ。**

### 4. メニューバーのアイコンを探す

- [ ] 見つかった / 見つからない
- [ ] 探すのにかかった時間: ______

### 5. MulmoTerminal を入れる

`環境` タブ → 未インストールのはず → `インストール`

- [ ] 表示は「未インストール」だったか
- [ ] インストールが通ったか

### 6. MulmoTerminal を操作する（#51 で直したところ）

`運用` タブで順に押す。**`~/.local/bin` 依存を外した箇所。**

- [ ] `開く` — ブラウザが開く。タブは1つだけか
- [ ] `再起動` — 動く。タブが開かないこと
- [ ] `停止` — 止まる
- [ ] `起動` — 上がる

### 7. 常駐（#12 で直したところ）

`環境` タブの `ログイン時起動・落ちたら再起動` が `オン` になっているか。

- [ ] オンになった

```bash
/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' \
  ~/Library/LaunchAgents/com.shutanuma.mulmoterminal.plist
```

- [ ] パスが出る
- [ ] `停止` を押すと解除される

### 8. 再ログイン

ログアウト → ログイン。

- [ ] MulmoTerminal が自動で上がった

---

## 片付け

退避で代用した場合は必ず戻す。

```bash
mv ~/.local/bin.bak ~/.local/bin
mv ~/Documents/Codex/SwiftBarTools.bak ~/Documents/Codex/SwiftBarTools
```

---

## 結果の記録

詰まった箇所は Issue にする。**「動いた」より「どこで止まったか」のほうが価値がある。**

---

# #15 を閉じる条件（2026-08-21 決定）

この手順書の上半分は **npm 配布に切り替える前** の実測記録。#15 に残っているのは
「ターミナルが要らない」の1点だけで、それは署名と公証（#54）が通って初めて確かめられる。

閉じる条件をここに固定する。**署名が通った日にこの節をそのまま実行する。**

## 前提（#54 が済んでいること）

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
xcrun notarytool history --keychain-profile mulmo-control | head -3
```

- [ ] Developer ID Application 証明書がある
- [ ] notarytool の資格情報が通る
- [ ] その状態で `./release.sh X.Y.Z` を通し、公証済みの版を出した

## 本番の確認（ここが #15 の本体）

**ブラウザで**（`curl` や `npx` ではなく）Releases から zip を落とす。
隔離マークを付けるのはブラウザなので、経路を変えると意味が無くなる。

```bash
xattr -p com.apple.quarantine ~/Downloads/MulmoControl.zip
```

- [ ] 隔離マークが**付いている**（付いていなければ、経路が違う。やり直す）

zip を展開し、`/Applications` にドラッグして、**ダブルクリックする**。

- [ ] **警告のダイアログが出ずに開いた** ← これが満たせたら #15 は閉じられる
- [ ] メニューバーにアイコンが出た

出なかった場合、何と出たかをそのまま記録する。「開発元を確認できません」と
「マルウェアが含まれていないことを検証できませんでした」は別の状態で、原因が違う。

## 裏取り

```bash
spctl -a -vv "/Applications/Mulmo Control.app"
codesign -dvv "/Applications/Mulmo Control.app" 2>&1 | grep -E "Authority|TeamIdentifier|flags"
xcrun stapler validate "/Applications/Mulmo Control.app"
```

- [ ] `spctl` が `accepted` / `source=Notarized Developer ID`
- [ ] `Authority=Developer ID Application: ...`、`TeamIdentifier=59FNRWS2H8`
- [ ] `flags` に `runtime`（hardened runtime）
- [ ] `stapler validate` が通る（チケットが貼られている＝オフラインでも通る）

`stapler` が通らないと、ネットワークが無い場所で初めて開く人だけが止められる。
手元では気づけない類なので、必ず見る。

## README の書き換え（閉じる前に済ませる）

#15 の当初の完成の定義は「README のインストール手順が zip をドラッグするだけになる」。
確認が通ったら README をその形に直してから閉じる。

- [ ] `## インストール` を **zip を落として Applications にドラッグ** に差し替える
- [ ] `npx mulmo-control` は「ターミナル派向け」として残す（消さない。#54 の判断ログどおり）
- [ ] 「なぜ zip をダウンロードして置く方式ではないのか」の節を消すか、
      **署名前の経緯**として書き直す（いま書いてあることは署名後には事実でなくなる）

## この節に含めないもの

素の Mac でボタンが一通り動くかは **#6** の担当。ここは**入り口だけ**を見る。
2つを混ぜると、入り口が通ったのか中が通ったのかが分からなくなる。
