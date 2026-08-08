# 進捗ボード — mulmo-control（2026-08-08）

## ✅ 完了したこと

- [x] v1.0.0 リリース公開（ユニバーサルバイナリ、Releases からのダウンロード方式）
- [x] install.sh の前提チェック（macOS 14 / npm / MulmoClaude / Swift コンパイラ、全て失敗経路を実測済み）
- [x] 2台の実機でインストール成功（M5 Air / 旧 Air。旧機は npm 回線エラー1回→再実行で完走）
- [x] BootCamp Slack で共有、最初の外部ユーザーの導入つまずき報告→修正済み
- [x] プロジェクト化（4点セット + Issue 一覧）
- [x] 別スレで PR #1〜#3 マージ済み（メニューバー案内・更新報告の正直化・MulmoClaude 任意化）

## 🔨 いまやっていること

- v1.0.8 まで公開済み（8/6〜8/8 に v1.0.2 から7本。うち5本は外部ベータ利用者が詰まった箇所の修正）
- Phase 2 着手。Issue #11（補助スクリプトのアプリ同梱）を実装中
- Issue は2系統ある: #1〜#7（別スレ発・コード監査系）と #8〜#15（このスレ発・配布ゴール系、#13 は #4 と重複で閉じた）
- open は11本（#18 は 8/8 にクローズ済み）

## ⏭ 残り

- GitHub の Issues 一覧が正。ここには書き写さない

## ⚠️ ハマりどころメモ

- アプリの入手経路が2つある（Releases ダウンロード / 手元ビルド）。テストは両方通すこと（MULMO_CONTROL_ZIP_URL で失敗を再現できる）
- クリーンルーム検証: 空の HOME を作って `env HOME=... ./install.sh`（/Applications への書き込みだけ sed で退避先に差し替える）
- 旧 Air の npm は ECONNRESET が出やすい（回線起因、再実行で通る）
- **同梱スクリプトは署名に封入される**（`Sealed Resources ... files=23`）。`scripts/` の中身を1バイトでも書き換えると `codesign --verify` が落ちるので、配布物のスクリプトを手で直さない。直すならソースを直して `build-app.sh` からやり直す
- **自己更新はバンドルの外に逃げてから走る**。`install.sh` が `/Applications/Mulmo Control.app` を `rm -rf` する一方、`mulmo-control-self-update` はその中から実行されるため。zsh はスクリプトを少しずつ読むので、消えたファイルの続きを読むと途中で死ぬ（`MULMO_SELF_UPDATE_DETACHED` で一度だけ再 exec している）
