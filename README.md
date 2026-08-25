# Mulmo Control

MulmoTerminal / MulmoClaude をメニューバーから起動・停止・更新する小さな macOS アプリです。

ターミナル操作に慣れていない人でも、Mulmo 系ツールを「入れる」「起動する」「落ちたら戻す」「最新版を確認する」まで触れることを目指しています。

## 紹介動画

何ができるアプリなのかを1分43秒でまとめた動画です（音声あり）。

[▶ 再生する](docs/intro.mp4)

## できること

- MulmoTerminal を開く / 起動 / 停止 / 再起動
- MulmoClaude を開く / 起動 / 停止 / 再起動
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

### リリース

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
- BootCamp Slack の `#p_mulmo_beta_users` に書いてもらっても届きます

作者の Mac で正しく見えてしまう不具合は、こちらでは気づけません。ダークモードで
文字が読めなくなっていた件も、使っている方が写真を送ってくれて初めて分かりました。
**「こんな細かいことで」と思うくらいのもので、ちょうどいいです。**

## License

MIT
