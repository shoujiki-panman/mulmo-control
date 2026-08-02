# Mulmo Control

MulmoTerminal / MulmoClaude をメニューバーから起動・停止・更新する小さな macOS アプリです。

ターミナル操作に慣れていない人でも、Mulmo 系ツールを「入れる」「起動する」「落ちたら戻す」「最新版を確認する」まで触れることを目指しています。

## できること

- MulmoTerminal を開く / 起動 / 停止 / 再起動
- MulmoClaude を開く / 起動 / 停止 / 再起動
- MulmoTerminal をログイン時に起動し、落ちたら再起動する LaunchAgent を設定
- MulmoTerminal / MulmoClaude / Mulmo 系 npm パッケージの最新版確認
- 更新があるとメニューバーアイコンで知らせる
- 更新後に、公式 Changelog から短い新機能要約を表示
- MulmoCast / MulmoCast Vision / MulmoBridge CLI / Slack Bridge の追加インストール
- ログ確認

## 対象

- macOS 14 以降
- Node.js / npm が入っているMac
- MulmoTerminal を `localhost:34567` で使いたい人
- MulmoClaude を `~/mulmoclaude` に置いて使う人

## インストール

```bash
git clone https://github.com/YOUR_NAME/mulmo-control.git
cd mulmo-control
./install.sh
```

インストール後、`/Applications/Mulmo Control.app` を開いてください。

初回は macOS の「ログイン項目と機能拡張」やセキュリティ設定で許可が必要になることがあります。

## アプリの見方

### 運用

普段使う画面です。

- `開く`: 起動していなければ起動してからブラウザで開きます
- `再起動`: サーバーを再起動します
- `停止`: サーバーを止めます
- `ログ`: ログの場所を確認します

### 追加

MulmoCast など、周辺ツールを追加します。

今の版では、追加ツールはこの画面から直接実行するのではなく、MulmoTerminal / MulmoClaude 側の作業から使う想定です。

### 環境

インストール状態、最新版、前回の更新内容を確認します。

## 置き場所

このアプリは以下を使います。

- アプリ: `/Applications/Mulmo Control.app`
- 補助スクリプト: `~/Documents/Codex/SwiftBarTools`
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

## 注意

これは個人用途から切り出した実験版です。

- Apple Developer ID 署名や notarization は未対応です
- MulmoClaude は `~/mulmoclaude` にある前提です
- UI やセットアップ導線はまだ改善中です
- macOS の `open` / LaunchServices の状態によっては、アプリの再認識に時間がかかることがあります

## License

MIT
