# Mulmo Control

MulmoTerminal / MulmoClaude をメニューバーから起動・停止・更新する小さな macOS アプリです。

ターミナル操作に慣れていない人でも、Mulmo 系ツールを「入れる」「起動する」「落ちたら戻す」「最新版を確認する」まで触れることを目指しています。

## 紹介動画

何ができるアプリなのかを1分43秒でまとめた動画です（音声あり）。

[▶ 再生する](docs/intro.mp4)

## できること

- MulmoTerminal を開く / 起動 / 停止 / 再起動
- MulmoClaude を開く / 起動 / 停止 / 再起動（連打しても二重に立ち上がりません）
- MulmoClaude の Telegram ブリッジを起動・停止といっしょに面倒を見る（既定はオフ）
- MulmoTerminal をログイン時に起動し、落ちたら再起動する LaunchAgent を設定
- MulmoTerminal / MulmoClaude / Mulmo 系 npm パッケージの最新版確認
- 更新があるとメニューバーアイコンで知らせる
- Mulmo Control 自身の最新版確認と更新
- 更新後に、公式 Changelog から短い新機能要約を表示
- MulmoCast / MulmoCast Vision / MulmoBridge CLI / Slack Bridge の追加インストール
- ログ確認

## 対象

- macOS 14 以降
- Node.js / npm（**アプリを入れるだけなら要りません**。MulmoTerminal / MulmoClaude を動かすのに要ります）
- MulmoTerminal を `localhost:34567` で使いたい人
- MulmoClaude を使う人（既定は `~/mulmoclaude`。別の場所も指定できます）

## インストール

1. [最新リリース](https://github.com/shoujiki-panman/mulmo-control/releases/latest) から `MulmoControl.zip` をダウンロード
2. 展開してできた `Mulmo Control.app` を `アプリケーション` フォルダにドラッグ
3. ダブルクリック

これだけです。ターミナルは要りません。

初回だけ「インターネットからダウンロードされました。開いてもよろしいですか？」と聞かれます。**「開く」を押してください。**2回目からは聞かれません。

このアプリはウィンドウも Dock アイコンも出しません。画面いちばん上の帯の右のほう、時計や Wi-Fi の並びに `>_` の形のアイコンが増えます。

### ターミナル派向け

```bash
npx mulmo-control
```

同じものが入ります。GitHub Releases からビルド済みのアプリを取ってきて `/Applications` に置き、そのまま起動します。Claude Code や MulmoTerminal と同じ流儀です。

### 署名について

v1.0.48 から、Apple が発行した Developer ID で署名し、公証（notarization）を通し、
チケットを貼ってあります。だから**ブラウザで落としてもそのまま開けます**。

それ以前は自己署名だったため、ブラウザ経由だと「マルウェアが含まれていないことを
検証できませんでした」と出て開けませんでした（macOS 15 以降は右クリック → 開く の
抜け道も塞がれています）。当時の逃げ道が `npx` で、隔離マークが付かない経路だから
開けていました。いまはどちらの経路でも開けます。

### 開発者向け: publish 前に手元で試す

```bash
npm pack
npx --package=./mulmo-control-<版>.tgz -- mulmo-control
```

`npx ./mulmo-control-<版>.tgz` と書くと `Permission denied` になります。npx はパスを「実行するファイル」と解釈するので、`--package=` で入れる物を、`--` の後ろで実行するコマンド名を、分けて渡す必要があります。公開後の `npx mulmo-control` では起きません。

### 開発者向け: 手元でビルドして入れる

```bash
git clone https://github.com/shoujiki-panman/mulmo-control.git
cd mulmo-control
./install.sh
```

`install.sh` は、ビルド済みのアプリを GitHub Releases からダウンロードして `/Applications` に置き、LaunchAgent の定義ファイルを用意します。`MULMO_CONTROL_BUILD=1 ./install.sh` で手元ビルドにもできます。

### MulmoClaude について

**先に入れておく必要はありません。** 無ければ「見つかりません」と伝えたうえで、そのままインストールを続けます。MulmoTerminal だけならそれで使えます。

MulmoClaude も使う場合は、次のどちらかです。

```bash
# まだ持っていない場合
git clone https://github.com/receptron/mulmoclaude.git ~/mulmoclaude

# 既に ~/mulmoclaude 以外に置いている場合
MULMOCLAUDE_DIR=/path/to/mulmoclaude ./install.sh
```

入れたあとに `./install.sh` をやり直すと、アプリが場所を覚えます。アプリの `運用` タブでも、未インストールなら `入手` ボタンから辿れます。

**clone が要るのは更新のためです。** このアプリは `git pull` で MulmoClaude を新しくするので、置き場所はリポジトリである必要があります。ただし**動かすのは通常モード**（`yarn dev` ではなく、作り置いた画面を配る形）なので、MulmoClaude の README が「開発者向け」と呼ぶ使い方にはなりません。作業中に画面が勝手に更新されることもありません。

MulmoClaude 自体のコードを直しながら使いたい人は、`運用` タブの MulmoClaude パネルにある `モード` から開発モードに切り替えられます。いまどちらで動いているかは、パネルの1行目に出ています。

ダウンロードできなかった場合は手元でビルドします（そのときだけ Xcode Command Line Tools が必要です）。`MULMO_CONTROL_BUILD=1 ./install.sh` で最初からビルドすることもできます。

定義ファイルを置くだけなので、インストールした時点ではまだ常駐しません。ログイン時起動と自動復帰が有効になるのは、アプリで `起動` を押したときです。`停止` を押すと解除されます。

インストールが終わると、アプリを起動して、どこを見ればいいかを案内するダイアログが出ます。

**このアプリはウィンドウも Dock アイコンも出しません。** 画面いちばん上の帯の右のほう、時計や Wi-Fi が並んでいるあたりに、ターミナルの形をした `>_` アイコンが増えるだけです。そこをクリックすると操作画面が開きます。

更新がある時は、このアイコンが下向き矢印の丸いアイコンに変わります。入れたての状態では更新ありになっていることが多いので、`>_` が見当たらない時はそちらを探してください。

メニューバーの項目が多い Mac やノッチ付きの Mac では、アイコンが表示しきれずに隠れることがあります。

起動しているか分からないときは、次で確認できます。

```bash
pgrep -lf MulmoControl
```

何も返らない場合は、直接実行するとエラーが読めます。

```bash
"/Applications/Mulmo Control.app/Contents/MacOS/MulmoControl"
```

初回は macOS の「ログイン項目と機能拡張」やセキュリティ設定で許可が必要になることがあります。

## アプリの見方

### 運用

普段使う画面です。

- `開く`: 起動していなければ起動してからブラウザで開きます
- `再起動`: サーバーを再起動します
- `停止`: サーバーを止め、ログイン時起動も解除します
- `ログ`: ログの場所を確認します

MulmoClaude の起動・再起動・更新が走っている間は、そのパネルのボタンが押せなく
なり、1行目に「○○の処理中です」と出ます。**通常モードの起動は画面を作り直すのに
1分ほどかかり、その間はまだ何も立っていません。** 立つまで押せたままだと、重ねて
押したぶんだけサーバーが増え、しかも空いている次のポート（3002, 3003…）へ逃げる
ので誰にも見えない状態で通知を送り続けます。`停止` だけは処理中でも押せます
（ビルド中に押せば、明けてからの立ち上げを中止します）。

`Telegram ブリッジ` の行をオンにすると、`yarn telegram` を MulmoClaude の起動・
停止といっしょに面倒を見ます。ブリッジの接続先は 3001 固定なので、オフのままだと
サーバーを立て直すたびに手で立て直すことになります。token などブリッジ側の設定は
MulmoClaude 側に置いてください（この画面では扱いません）。

### MulmoTerminal 画面ガイド

運用タブの `MulmoTerminal 画面ガイド` をオンにすると、**`開く` から開いた MulmoTerminal
の画面で、カーソルを合わせたところに日本語の説明が出ます**。ブラウザ拡張は要りません。

仕組み: `開く` を押すと、Mulmo Control が MulmoTerminal の前に小さな中継
（`127.0.0.1:34598`）を立て、画面にだけ説明のスクリプトを差し込みます。ターミナルの
入出力は触らずにそのまま通します。

- **ブックマークなどで `localhost:34567` を直接開いたときは出ません。** 出したいときは `開く` から開いてください
- 中継を通すとアドレスが変わるので、**グリッドの並びなどブラウザ側に保存される状態は、最初の1回だけ並べ直し**になります
- オフにすると `開く` は今までどおり MulmoTerminal を直接開きます。中継が立てられないとき（node が無い・ポートが塞がっている）も直接開きます
- 中継はこの Mac の中からしか入れず（ループバック限定）、よそのサイトからの接続は断ります。MulmoTerminal はターミナルそのものなので、ここは `check.sh` が毎回、実際に接続を投げて確かめています

### 追加

MulmoCast など、周辺ツールを追加します。

今の版では、追加ツールはこの画面から直接実行するのではなく、MulmoTerminal / MulmoClaude 側の作業から使う想定です。

### 環境

インストール状態、最新版、前回の更新内容を確認します。

Mulmo Control 自身に更新がある場合もここで確認できます。更新があるとメニューバーアイコンが変わり、上部の `アプリ更新` から更新できます。

## 置き場所

このアプリは以下を使います。

- アプリ: `/Applications/Mulmo Control.app`
- 補助スクリプト: アプリの中（`Mulmo Control.app/Contents/Resources/scripts`）
- ログ: `~/Library/Logs/Mulmo Control`
- MulmoTerminal データ: `~/.mulmoterminal`
- MulmoTerminal 実行ファイル: `~/.local/bin/mulmoterminal`
- MulmoClaude リポジトリ: `~/mulmoclaude`
- モード・Telegram ブリッジの設定: `~/Library/Application Support/Mulmo Control`

## アンインストール

```bash
./uninstall.sh
```

アプリと LaunchAgent は削除します。`~/.mulmoterminal` のログやセッションデータは残します。

## 開発

```bash
./build-app.sh
```

ビルド結果は `build/Mulmo Control.app` にできます。

### 見た目を手元で確かめる

```bash
./try.sh            # いまのブランチをビルドして、動いているアプリを差し替える
./try.sh main       # main に切り替えてから同じことをする
```

pull → ビルド → 動いているアプリを止める → 差し替える → 起こす、を一度にやります。
**途中で1つでも失敗したらそこで止まり**、最後に入れたコミットを名乗ります。

これを手で繋いでいたとき、ビルドが失敗しても古い `build/` が黙って入る・古いプロセスが
生きたまま前の画面が出続ける・`main` を pull していてブランチの変更が入っていない、の
3つを1晩で踏みました。どれも「入れ替わったつもり」で終わって気づけません。

配ったものには触りません。**`アプリ更新` を押すと配布版に戻ります。**

### リリース

**GitHub の画面から出す**のがいちばん楽です。[Actions → release](https://github.com/shoujiki-panman/mulmo-control/actions/workflows/release.yml)
を開き、`Run workflow` を押して、版（`1.0.70` のように）とリリースノートを入れて `Run workflow`。
ビルド → 検証 → 公証 → zip → タグ → Releases → 取り直して確認、まで GitHub 側で走ります。
手元の Mac は閉じてかまいません。

- リリースノートの改行は `\n` と書きます（入力欄が1行なので）。空にすると、前の版から入った PR の題を並べます
- 同時に2回押しても1本ずつ走ります。タグを push しても出ません（入口は手動だけ）
- 中で動くのは下の `release.sh` そのものです。手順は2箇所に書いていません

初回だけ、署名と公証の資格情報を GitHub に預ける必要があります。**手元の Mac で1コマンド**です。

```bash
./release-setup.sh
```

Developer ID 証明書をキーチェーンから書き出し、公証に使う Apple ID と App用パスワード
（[appleid.apple.com](https://appleid.apple.com) → サインインとセキュリティ → App用パスワード で作る）を
聞いて、5つを Secrets に預けます。途中で macOS が「鍵を書き出してよいか」を1回聞くので `許可` を押します。
預けたものは Apple 側でいつでも無効にできます。

手元から出すこともできます。

```bash
./release.sh 1.0.14                 # リリースノートはエディタで書く
./release.sh 1.0.14 -F notes.md     # ファイルから読む
./release.sh 1.0.14 --dry-run       # 出さずに、ビルドと検証だけ通す
```

`Info.plist` の版を書き換え、ビルドし、**Apple の公証に出して**、チケットを貼り、zip にして
Releases を作るまでを一度にやります。公証は Apple 側の審査なので **数分待ちます**
（`Current status: In Progress...` が並びます）。固まったわけではありません。

公証には Developer ID 証明書と、`notarytool` の資格情報（keychain profile 名 `mulmo-control`）が
要ります。どちらも無いときは公証を飛ばし、自己署名のまま出します。**止まりません。**

配る前後に確認も入ります。版がそろっているか、補助スクリプトが `scripts/` と同じ本数だけ同梱されたか、署名が通るか、空白を含むパスから実行できるか。最後に**利用者と同じ URL から zip を取り直して**、配信されているものが期待どおりか確かめます。

途中で1つでも合わなければそこで止まります。

## 注意

これは個人用途から切り出した実験版です。

- MulmoClaude の場所はインストール時に `MULMOCLAUDE_DIR` で変えられます
- `claude` と `codex` は PATH から探すので、Homebrew でも npm global でも動きます
- UI やセットアップ導線はまだ改善中です
- macOS の `open` / LaunchServices の状態によっては、アプリの再認識に時間がかかることがあります

## 気づいたことがあれば

**うまくいかない、変な見え方をする、こうだったらいいのに — どれでも歓迎です。**

- [Issue を立てる](https://github.com/shoujiki-panman/mulmo-control/issues/new) — スクリーンショットが1枚あると、それだけで原因が分かることがよくあります
- 既にある Issue へのコメントでも構いません

作者の Mac で正しく見えてしまう不具合は、こちらでは気づけません。ダークモードで
文字が読めなくなっていた件も、使っている方が写真を送ってくれて初めて分かりました。
**「こんな細かいことで」と思うくらいのもので、ちょうどいいです。**

## License

MIT
