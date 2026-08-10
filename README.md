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
- Node.js / npm が入っているMac
- MulmoTerminal を `localhost:34567` で使いたい人
- MulmoClaude を使う人（既定は `~/mulmoclaude`。別の場所も指定できます）

## インストール

```bash
git clone https://github.com/shoujiki-panman/mulmo-control.git
cd mulmo-control
./install.sh
```

`install.sh` は、ビルド済みのアプリを GitHub Releases からダウンロードして `/Applications` に置き、LaunchAgent の定義ファイルを用意します。npm が見つからない場合は、何も書き込む前に理由を出して止まります。

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
- ログ: `~/Documents/Codex/SwiftBarLogs`
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

`Info.plist` の版を書き換え、ビルドし、zip にして Releases を作るまでを一度にやります。

配る前後に確認も入ります。版がそろっているか、補助スクリプトが `scripts/` と同じ本数だけ同梱されたか、署名が通るか、空白を含むパスから実行できるか。最後に**利用者と同じ URL から zip を取り直して**、配信されているものが期待どおりか確かめます。

途中で1つでも合わなければそこで止まります。

## 注意

これは個人用途から切り出した実験版です。

- Apple Developer ID 署名や notarization は未対応です
- MulmoClaude の場所はインストール時に `MULMOCLAUDE_DIR` で変えられます
- `claude` と `codex` は PATH から探すので、Homebrew でも npm global でも動きます
- 補助スクリプトとログの置き場所（`~/Documents/Codex/...`）はまだ固定です
- UI やセットアップ導線はまだ改善中です
- macOS の `open` / LaunchServices の状態によっては、アプリの再認識に時間がかかることがあります

## License

MIT
