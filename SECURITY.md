# SECURITY.md

Mulmo Control の検査カタログ。出典は Issue #67。

このファイルは**現状の申告**であって、達成の宣言ではない。印が付いていない項目は
「まだ見ていない」という意味で、安全だと分かっているという意味ではない。

## 印の意味

| 印 | 意味 |
|---|---|
| ✅ | `check.sh` が自動で見ている。壊すと PR で落ちる |
| 🔨 | 実装はあるが自動検査は無い。人が変えれば黙って壊れる |
| ⛔ | 項目自体が無効になった |
| （空欄） | 未着手 |

## gate の分け方

| gate | いつ走るか |
|---|---|
| fast | PR ごと（`check.sh`） |
| release | 配る前（`release.sh` → `check.sh`） |
| manual | 人が触って確かめる |
| sandbox | 使い捨ての環境で走らせる |
| governance | 運用ルール。自動化しない |


## A. config/env parsing

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 001 | fast | `app-info.env` が存在しない場合は既定値に落ちる | ✅ 設定は許可したキーだけを返す |
| 002 | fast | 空の `app-info.env` で落ちない | ✅ 同上 |
| 003 | fast | 正常な `MULMO_CONTROL_REPO_URL` を読める | ✅ 同上 |
| 004 | fast | 正常な `MULMO_CONTROL_SOURCE_DIR` を読める | ✅ 同上 |
| 005 | fast | 正常な `MULMO_CONTROL_BRANCH` を読める | ✅ 同上 |
| 006 | fast | 正常な `MULMO_CONTROL_MULMOCLAUDE_DIR` を読める | ✅ 同上 |
| 007 | fast | 未知のキーは無視する | ✅ 同上 |
| 008 | fast | `touch /tmp/...` のような行は実行されない | ✅ 設定を source していない |
| 009 | fast | `$(...)` を含む値/行は実行されない | ✅ 同上 |
| 010 | fast | backtick を含む値/行は実行されない | ✅ 同上 |

008〜010 の ✅ は、最初は**過大申告だった**（#83）。ガードが `"${CONFIG}"` という綴りだけを
探しており、`$CONFIG`・変数名違い・パス直書き・一行の `&&` は素通りしていた（5通り中4通り）。
現在は「`mulmoterminal-agent-env` 以外を `.` / `source` していたら落とす」という whitelist に
変えてあり、5通りすべてで落ちることを実測済み。**禁止したい綴りを並べる形では勝てない。**

## B. quoting/path safety

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 011 | fast | パスに空白があっても command string が壊れない | ✅ 起動スクリプトは空白入りの場所を切らずに渡す |
| 012 | fast | パスに `'` があっても config parser が読める | ✅ 設定は許可したキーだけを返す |
| 013 | fast | MulmoClaude dir に空白があっても start script が壊れない | ✅ 起動スクリプトは空白入りの場所を切らずに渡す |
| 014 | fast | MulmoClaude dir に `'` があっても LaunchAgent plist が壊れない | ✅ plist は & < > ' を含む場所を往復できる |
| 015 | fast | `/Applications/Mulmo Control.app` を裸で shell に埋め込まない | ✅ tool()/bin() を通している |
| 016 | fast | `toolsDir` は Swift 側で helper 経由になる | ✅ 同上 |
| 017 | fast | `localBin` は Swift 側で helper 経由になる | ✅ 同上 |
| 018 | fast | XML plist 値に `&` / `<` / `>` が入っても escape される | ✅ 同上 |
| 019 | fast | log path に空白があっても tail/open が壊れない |  |
| 020 | fast | app bundle内の同梱scriptを空白入りpathから実行できる | ✅ 空白入りパスからの実行 |

## C. shell safety

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 021 | fast | shell entrypoint は shebang を持つ | ✅ 全スクリプトにシェバンがある |
| 022 | fast | shell entrypoint は `set -u` または `set -eu` を持つ | ✅ set -u / set -eu がある |
| 023 | fast | `curl | sh` / `wget | sh` がない | ✅ 落としたものの丸投げ・eval・権限昇格がない |
| 024 | fast | `eval` がない | ✅ 同上 |
| 025 | fast | `sudo` がない | ✅ 同上 |
| 026 | fast | 許可していない `rm -rf` がない | ✅ rm -rf の対象は決まった3つだけ |
| 027 | fast | `rm -rf` は固定された安全な対象か temporary dir に限定される | ✅ 同上 |
| 028 | fast | script syntax を `zsh -n` で検査する | ✅ zsh -n による構文検査 |
| 029 | fast | background job による `nice(5)` 警告が検査出力に出ない |  |
| 030 | fast | helper script が同梱scripts数に含まれる |  |

## D. install/uninstall

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 031 | release | macOS 14 未満で install が止まる |  |
| 032 | release | npm がない場合に install が明確に止まる |  |
| 033 | release | MulmoClaude がない場合も MulmoTerminal用途では install が続く |  |
| 034 | release | `MULMOCLAUDE_DIR` 指定が app-info.env に保存される |  |
| 035 | release | build済みzip取得成功時は local build に落ちない |  |
| 036 | release | zip取得失敗時は local build に fallback する |  |
| 037 | release | `MULMO_CONTROL_BUILD=1` で必ず local build する |  |
| 038 | release | install後に `/Applications/Mulmo Control.app` が存在する |  |
| 039 | manual | uninstall は app と LaunchAgent を消し、ログ/データは残す |  |
| 040 | manual | uninstall 後に再installできる |  |

## E. self-update

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 041 | fast | self-update check は installed version を Info.plist から読む | ✅ ソースの HEAD ではなくアプリ自身から読んでいることを見る（#31） |
| 042 | fast | release tag が読めない時は `unknown` status を書く | ✅ 上流を確かめられないときは unknown と書く |
| 043 | fast | installed が latest と同じなら `current` | ✅ `mulmo-version-status` を**実際に動かして**10通りと突き合わせる |
| 044 | fast | installed が latest より新しければ `current` | ✅ 同上（手元ビルドがリリースより先の場合） |
| 045 | fast | installed が古ければ `update` | ✅ 同上。1.0.9 と 1.0.53 が**文字列比較で逆になる**ことも見る |
| 046 | fast | self-update apply は detached copy で動く |  |
| 047 | release | source repo が既存gitなら fetch/pullする |  |
| 048 | release | source repo がなければ cloneする |  |
| 049 | release | apply 失敗時に log が残る |  |
| 050 | manual | self-update 後にアプリを再起動できる |  |

## F. MulmoTerminal/LaunchAgent

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 051 | fast | `mulmoterminal-agent-env` は sibling script として読まれる |  |
| 052 | fast | LaunchAgent plist は `plutil -lint` に通る | ✅ 同上 |
| 053 | fast | LaunchAgent WorkingDirectory がない時は `$HOME` に逃がす | ✅ 場所が無いときは HOME に逃がす |
| 054 | fast | locale fallback `LANG=C.UTF-8` が start script にある | ✅ 起動スクリプトのロケール補完 |
| 055 | fast | 既にport 34567が応答中なら二重起動しない | ✅ 起動前に二重起動を避けている |
| 056 | manual | 起動ボタンで LaunchAgent が bootstrap される |  |
| 057 | manual | 停止ボタンで LaunchAgent が bootout される |  |
| 058 | manual | 再起動ボタンで kickstart または再起動できる |  |
| 059 | manual | keepalive-enabled の作成/削除が期待通り | ⛔ keepalive-enabled は廃止した（表示専用で何も制御していなかった） |
| 060 | manual | 自動起動したMulmoTerminalで日本語が `_` にならない | 🔨 #62 で修正・実機で実測 |

## G. MulmoClaude repo states

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 061 | fast | MulmoClaude dir が存在しない場合に status が分かる | ✅ 場所が無い・git repo でないときは止まる |
| 062 | fast | MulmoClaude dir がgit repoでない場合に update が止まる | ✅ 同上 |
| 063 | sandbox | dirty worktree は stash される | ✅ 退避を戻せずに壊れたら止まる |
| 064 | sandbox | stash 失敗時は update を中止して理由を残す | ✅ 退避に失敗したら、その先へ進まない |
| 065 | sandbox | default branch 以外なら default branch に戻す | ✅ 別のブランチを見ていたら既定のブランチに戻す |
| 066 | sandbox | checkout 失敗時は stash を戻す | ✅ 既定のブランチに戻せなければ退避を戻してから止まる |
| 067 | sandbox | pull失敗時は stash を戻す | ✅ pull に失敗したら退避を戻してから止まる |
| 068 | sandbox | pullで変化なしなら「すでに最新」理由を残す | ✅ 変化が無いときは「すでに最新」と言う |
| 069 | sandbox | yarn install 失敗時は理由を残す | ✅ yarn install に失敗したら理由を残す（手元のみ。CI の yarn は壊れた package.json でも成功するので飛ばす） |
| 070 | manual | update後にMulmoClaudeを再起動する |  |

## H. npm/network/update checks

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 071 | fast | node がない時に update cache が `Node未検出` になる | ✅ node が無いときは「Node未検出」と言う |
| 072 | fast | npm がない時に npmLatest が `unknown` になる | ✅ npm を外した使い捨て環境で実際に走らせる |
| 073 | fast | npm latest timeout で落ちない |  |
| 074 | fast | MulmoTerminal version parse が SemVer を拾う |  |
| 075 | fast | package.json workspace package version を拾う |  |
| 076 | fast | dependency version の `^` / `~` を剥がす |  |
| 077 | fast | unknown がある時 summary が `一部未確認` | ✅ npm が答えない環境で summary を見る |
| 078 | fast | update がある時 summary が件数を出す | ✅ 件数が items の実数と合うかまで見る |
| 079 | release | `mulmo-npm-install` は一時的な失敗を1回だけ retry する | ✅ 呼び出しが2回・待ちがあることを見る |
| 080 | release | npm cache は `/private/tmp` 側を使う | ✅ 既定値の綴りを見る |

## I. logs/status JSON

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 081 | fast | self-update status JSON が valid JSON | ✅ 同上 |
| 082 | fast | mulmo updates cache が valid JSON | ✅ 更新の一覧は形を保つ |
| 083 | fast | update reasons が tab-separated で読める | ✅ 更新の理由はタブ区切りで読める |
| 084 | fast | last update summary が存在しない時もUIが落ちない | ✅ 更新していない人には要約ファイルを作らない |
| 085 | fast | legacy log dir から新log dirへの逆戻りがない | ✅ ~/Documents/Codex を参照していない |
| 086 | fast | logs path は `~/Library/Logs/Mulmo Control` に揃う | ✅ ログの置き場所は1つだけ |
| 087 | manual | ログボタンで正しいログ場所を開く |  |
| 088 | manual | status UI に `unknown/current/update/missing` が出る |  |
| 089 | manual | 通知済みkeyで同じ通知を繰り返さない |  |
| 090 | manual | app self-update通知とtool update通知が混ざらない |  |

## J. release/artifact/AI governance

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 091 | fast | Info.plist と package.json の version が一致する | ✅ Info.plist と package.json の一致 |
| 092 | fast | `bin/mulmo-control.mjs` が `node --check` に通る | ✅ bin/mulmo-control.mjs の構文 |
| 093 | release | app bundle の scripts 数が source と一致する | ✅ 同梱スクリプト数 |
| 094 | release | codesign verify がクリーンコピーで通る | ✅ codesign verify |
| 095 | release | zip はクリーンコピーから作る |  |
| 096 | release | release後に latest zip を取り直してversion確認する | ✅ 取り直しと版の比較の両方を見る |
| 097 | governance | AI reviewer は最初 shadow mode でコメントのみ |  |
| 098 | governance | AIが作業開始時にIssueへ方針コメントを残す | 🔨 #67 に方針コメントを残した（当初は守れていなかった） |
| 099 | governance | 自動承認する場合は一定割合を人間がsample reviewする |  |
| 100 | governance | 新しいbug classが見つかったら `SECURITY.md` / `check.sh` に戻す | 🔨 #83 で1周した（ガードの穴 → Issue → 検査 → ここへ反映） |
| 101 | fast | 自己更新は、写しに連れて行かない兄弟スクリプトを使わない | ✅ 参照と cp の対象を突き合わせる |
| 102 | fast | 追加ツールを入れる場所と、版を読む場所が同じ | ✅ 綴りを突き合わせる（#129 で実際に食い違った） |
| 103 | fast | 更新一覧の項目は、どれかのボタンで更新できる | ✅ 一覧と追加ツールの id を突き合わせる（#131） |
| 104 | fast | 古い置き場所の引き継ぎは一度きり（毎起動で ~/Documents を読まない） | ✅ 印の guard があることを見る（#134） |
| 105 | fast | 「前回の更新」に残った失敗は、解消したら解消したと添える | ✅ 添える側が消えていないかを見る（#136） |
| 106 | fast | 停止中のサービスに、起動する手段が画面から見える | ✅ ServicePanel の中で startAction が2箇所から呼ばれることを見る（#139） |
| 107 | fast | 起こす MulmoClaude に、呼び出し元の PORT を引き継がせない | ✅ yarn dev を起こす行が PORT を外していることを見る（#141） |
| 108 | fast | 配色が、明るいとき/暗いときの外観に応じて変わる | ✅ Palette の各行が adaptive( を通っていることを見る（#143） |

## K. スマホ連携の鍵

出典は Issue #145 と #154。Mulmo Control は「スマホ連携」の session blob を
Keychain に預かる。中身は Firebase の refreshToken なので、扱いを間違えると
**平文でログに残る／アンインストールしても残る**という形になる。

預かる先は**2つある**。MulmoClaude 側（#145）と MulmoTerminal 側（#154）で、
同じ Google アカウントを使うが接続は別々なので blob も別。#145 のときに
MulmoTerminal 側を入れ忘れ、同じ「まだ繋いでいません」に対して片方だけが
「繋ぐ」を出し、もう片方は設定画面へ送っていた（#154 で実測）。

| # | gate | 内容 | 状況 |
|---|---|---|---|
| 109 | fast | 預かった鍵/トークンを `echo` / `tee` に渡さない（ログに平文で残る） | ✅ 繋ぎ直す2つのスクリプトと check を対象に、秘密を持つ変数が出力コマンドに渡っていないかを見る |
| 110 | fast | 鍵の置き場所（service / account）の綴りを共有定義だけが持つ | ✅ 直書きを禁じ、Keychain を触る箇所が消えていないかを見る |
| 111 | fast | 401（期限切れ）と `uninstall.sh` の両方に鍵を捨てる口がある | ✅ **繋ぎ直す2本とも**と、`uninstall.sh` が**2つとも**消していることを見る |
| 112 | fast | 繋がっているときに reconnect を叩かない（#23 / #147 で 401 を実測） | ✅ **両方**の繋ぎ直しスクリプトで、引き返す判定が POST より前にあることを行番号で見る |
| 113 | manual | 預かった鍵を読むときに Keychain の許可ダイアログが出ない | |
| 114 | manual | MulmoClaude を止めた状態から `繋ぐ` の1押しで緑に戻る | 🔨 2026-08-28 に実測（14.6秒・ブラウザ無し） |
| 115 | fast | 状態の全組み合わせで、スマホ連携の行に出る言葉が対応表と一致する | ✅ `StatusDisplay.swift` と検査を `swiftc` で組んで**実際に走らせる**（12通り） |
| 126 | fast | 預かる先の名前が2つで分かれている（同じだと後から預けたほうが先を潰す） | ✅ 共有定義の2つの service 名が違うことを見る |

126 がここ（K 節）にあって L 節（116〜125）より後ろなのは、#152 と並行で
作ったため。番号は付けた順であって、節の順ではない。

## L. プロジェクトのセッション（Issue #152）

スマホから使うためのリモートセッションを、ディレクトリごとに立てる。動いて
いるかは**自分が立てた pid の生死**で見る。`claude agents --json` は使わない
（同じフォルダで人が手で開いたセッションにも当たり、止めたのに「動作中」と
出た。remote-control が有効かも教えない）。

| # | gate | 何を守るか | どう見るか |
|---|---|---|---|
| 116 | fast | `claude` の信頼フラグ（`hasTrustDialogAccepted`）を書かない | ✅ 書き込みの形を禁じ、読む側が消えていないことも見る |
| 117 | fast | `projects.json` を shell として実行しない（#67 と同じ穴） | ✅ `json.load` で読み、`source` / `.` が無いことを見る |
| 118 | fast | プロジェクトの行に出る言葉とボタンが対応表と一致する | ✅ 実在 × 動作 × 信頼の8通りを**実際に走らせる** |
| 119 | manual | 登録したディレクトリのセッションが、スマホから見える |  |
| 120 | fast | セッションの画面出力を保存しない（会話が平文で残る） | ✅ 起動行を畳んで `>/dev/null` に落としていることを見る |
| 121 | fast | 止めるのは自分が立てたものだけ（人が開いた作業中のものを消さない） | ✅ `pkill` / `killall` を禁じ、控えた pid で止めていることを見る |
| 122 | fast | 登録の名前が重ならない（名前は控えの鍵。重なると片方を止めて両方消える） | ✅ 同名フォルダ2つを**実際に登録して**、別の名前が付くことを見る |
| 123 | fast | はずす前に止める（止める口の無いセッションを残さない） | ✅ `mulmo-project-stop` の呼び出しが、登録を書き換える行より前にあることを見る |
| 124 | fast | 登録の書き換えは一時ファイル経由で入れ替える（半分の JSON を残さない） | ✅ 書く3本すべてに `os.replace` があることを見る |
| 125 | fast | 読めない登録の上に書かない（手で直している最中の登録を、他ごと消さない） | ✅ 壊した `projects.json` に**実際に足してみて**、失敗し、中身が変わらないことを見る |

### 防げていないこと（申告）

**blob は `security add-generic-password -w <値>` の引数として渡している。**
同じ利用者の `ps` から一瞬見える。

これは解決していない。stdin から流す道もあるが、**`-w` に値を stdin で渡すと 128 バイトで
黙って切り捨てられる**（実測: 2100 バイトの blob が 128 バイトになり、エラーは出ない）。
気づけない壊れ方なので採らなかった。

そもそも同じ利用者は `.session-token` を読んで `/api/remote-host/status` を直に叩けるので、
blob はそちらからも取れる。ここで防いでいるのは**ファイルとして残ること**（ログ・バックアップ・
アンインストール後）であって、同一利用者からの読み取りではない。**印を付けない。**

114 は 2026-08-28 に通しで確かめた。MulmoClaude を止め、ブラウザのタブも閉じた状態から
スクリプトを叩き、**起動 → 3001 の応答待ち → 控えた blob で reconnect → 緑**まで 14.6 秒。
`#23` に「成功経路は未確認」と残っていた穴も、これで埋まった。ただし**自動検査は無い**ので 🔨。

113 は署名済みバンドルの中のスクリプトから読んで 0.3 秒で返っている（ダイアログが要るなら
そこで止まる）が、**アプリ本体を親にして呼んだ場合は見ていない**。印は付けない。

## 現状

| 状況 | 件数 |
|---|---|
| ✅ `check.sh` が見ている | 85 |
| 🔨 実装はあるが自動検査なし | 4 |
| ⛔ 無効 | 1 |
| 未着手 | 36 |

101 は 100番（新しい壊れ方を見つけたらここへ戻す）を1周させて足したもの。
自己更新の写しが `mulmo-config-get` しか連れて行かないことに気づいたが、
そのときは自己更新そのものを触るのが危ないと判断して手を出さなかった。
**壊れ方だけ先に検査へ落としてある。**

**実装があることと、壊れたら気づけることは別。**「作者の環境では正しく見える」
不具合が1日で6件出たのは後者が無かったためで、🔨 を ✅ に移すのがこの表の使い道。

残る 🔨 4件は、`check.sh` では見られないもの。

- **060** は自動起動した MulmoTerminal の**見え方**そのもの。ロケールを補う行が
  あることは見ているが、日本語が潰れないことは画面を見ないと分からない
- **098 / 100** は人の運用（Issue に方針を書く・見つけた壊れ方をここへ戻す）で、
  コードの形では表せない

無理に ✅ にしない。**印が実態と違うことのほうが害が大きい**（085 で一度踏んだ）。

## 新しい壊れ方を見つけたら

項目を足して `check.sh` に検査を入れる（100番）。**検査を書いたら必ず
「壊したら落ちるか」を試すこと。** 同日中に4回、効いていない検査を
「効いた」と誤読しかけた。踏んだ罠:

- 変数名で探すと、その話をしている**自分のコメント**に当たる
- `grep -v` で行を消して否定テストを作ると**構文エラー**になり、検査の手前で落ちる
- コメント行をシェバンより前に置くと、シェバン検査ごと飛ばされる
- `grep -vE ':[[:space:]]*(#|//)'` は **URL の `://`** に当たる
- **カタログの印そのものを間違えることがある。** 085 は `check.sh` が既に見ていたのに
  🔨 と書いていた。印を付ける前に、対応するガードが実在するか `check.sh` を検索する
- 消す対象の綴りを確かめずに `sed` すると、何も消えないまま「素通り」と出る
- **zsh は引用符を外しても単語に分かれない**（sh と違う）。引用符を外して壊れないことは、
  検査が効いていない証拠にならない。空白で実際に壊れるのは #32 の形 ——
  コマンドを1本の文字列に組んで `zsh -c` に渡すとき
