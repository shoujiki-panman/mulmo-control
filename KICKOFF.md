# KICKOFF — mulmo-control（2026-08-03）

## ゴール

**入れるのにターミナルが要らない状態にする。**
ターミナルを開きたくない人のための道具なのに、インストールにだけターミナルが要る。この矛盾を消すのが第一段階で、完成の定義は「zip を Applications にドラッグするだけで使い始められる」。

配ること自体は 2026-08-02 に達成済み（公開・v1.0.0・他人の Mac で動作）。以降は、届けたい相手に本当に届く形にするフェーズ。

## やらないこと（スコープ外を先に決める）

- Apple Developer ID 署名・notarization（お金がかかる。求められるまでやらない）
- Windows / Linux 対応
- MulmoTerminal 本体の機能追加（それは上流 receptron/mulmoterminal の話）
- 多言語化（日本語のみ）

## 運用ルール

- Issue → ブランチ → 実装 → チェック → PR → マージ の1周を崩さない（有本さん流）
- PR は意味のある最小粒度。1 Issue = 1 PR
- バージョンは semver。修正 = patch（v1.0.1）、機能 = minor（v1.1.0）
- アプリの挙動が変わるマージのたびに GitHub Releases を更新する（build → zip → gh release）

## フェーズ計画

- Phase 0: プロジェクト化（完了条件: 4点セットと Issue 一覧が GitHub にある）
- Phase 1: 小さい修繕でフローを1周回す（完了条件: Issue → PR → マージ → リリース更新を最低1周。npm リトライ・初回起動通知・バージョン表示）
- Phase 2: 自己完結化（完了条件: install.sh 無しでアプリ単体が全機能動く。スクリプト同梱・LaunchAgent 自書き・固定パス廃止）
- Phase 3: zip ドラッグ配布（完了条件: README の手順が「zip を落として Applications へドラッグ」だけになる。リリース1コマンド化）
- Phase 4: 使い続けるのにターミナルが要らない（完了条件: 詰まったときに何が起きているかがメニューバーで分かり、復旧の入口まで1クリックで行ける。第1号は #17 claude のログイン切れ）

## 参考（リポ・記事・公式手順）

- 本体リポ: https://github.com/shoujiki-panman/mulmo-control
- 上流: https://github.com/receptron/mulmoterminal / https://github.com/receptron/mulmoclaude
- 開発フローは BootCamp 標準（Issue→ブランチ→実装→チェック→PR→マージ）

※公式の手順は省略・最適化せずそのまま再現する
