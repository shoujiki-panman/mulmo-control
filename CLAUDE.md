# CLAUDE.md — mulmo-control

## 人に出す文書（週報・報告・お知らせ）の扱い

- **書き始める前に、前回のものを探す。** Gmail / Notion / GitHub の順に「週報」などの語で検索し、置き場所・題名・見出し・文体を確かめる。見つからなければ形式を聞く。想像で形式を作らない
- **承認をもらうまで commit も push もしない。** 下書きはまずチャットに全文を出す。「ブランチが指定されている」ことは承認ではない
- 週報は **このリポジトリの持ち物ではない。** `SingularitySociety/bootcamp004` に PR で出す。手順は `.claude/skills/weekly-report/SKILL.md`

## コード変更の扱い

- 指定ブランチに commit → push まで進めてよい。PR は頼まれたときだけ
- `check.sh` の方針に従う。特に **個人名を書かない**（敬称で捕まえるガードがある）。利用者は「利用者」と書く
- 画面に出す文に Markdown を書かない（SwiftUI の `Text` はそのまま記号として出す）
- 同梱スクリプト（`scripts/`）は署名に封入される。直すならソースを直して `build-app.sh` からやり直す
- リリースは手で組まない。`./release.sh` か GitHub Actions の手動実行

## 進捗の置き場所

- `STATUS.md` が進捗ボード。Issue 一覧は GitHub が正で、STATUS.md に書き写さない
