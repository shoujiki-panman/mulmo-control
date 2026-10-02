// MulmoTerminal 画面ガイド（日本語）
//
// MulmoTerminal の画面に、カーソルを合わせると日本語の説明が出るようにする。
// **ブラウザ拡張は使わない**（Issue #207）。Mulmo Control が MulmoTerminal の前に
// 中継（scripts/mulmoterminal-guide-proxy.mjs）を立て、画面の HTML にだけこの
// ファイルを差し込む。中継を通った画面（127.0.0.1:34598）で出る。
//
// 経緯: 最初は Tampermonkey のユーザースクリプトとして作ったが、本人は拡張を
// 入れない方針で、**Tampermonkey は一度も入っていなかった**。#202 で「拡張が
// 消えた」と書いたのは誤り。

(() => {
  "use strict";

  // ── 説明文 ──────────────────────────────────────────────────
  //
  // 1つの説明は **[何をするか, どんな時に使うか]** の2段（Issue #224）。
  // 1段だけだと「コードをコピーします」までは分かっても、それを**いつ押すのか**が
  // 分からない、と言われた。ターミナルに慣れていない人が読む前提で書く。
  // 長さの上限は tests/guide-text-test.mjs が見ている（吹き出しをはみ出させない）。
  //
  // 当てる先は **`data-testid` と `aria-label`** にする。見えている文字で
  // 当てると、上流が言い回しを変えた日に黙って外れる。印なら、消えたときは
  // 説明が出ないだけで、間違った説明は出ない。印が今の MulmoTerminal に実在するかも
  // 同じ検査が見ている（入っている Mac のとき）。
  //
  // 知らない要素には何も出さない。埋めることより、嘘を出さないことを取る。
  const BY_TESTID = {
    // ── 画面の上の帯 ──
    "machine-load": [
      "この Mac の混み具合です。数字が大きいほど忙しい状態です。",
      "反応が鈍いと感じたときに見ます。数字が大きければ、使っていないセルを閉じると軽くなります。",
    ],
    // ── セルの見出し ──
    "cell-header-main": [
      "このセルの見出しです。フォルダ・git の状態・モデル・使った量が1行に並びます。",
      "セルがたくさん並んで、どれが何の作業か分からなくなったときに、ここで見分けます。",
    ],
    "dir-icon": [
      "このフォルダの目印です。プロジェクトごとに色と絵を変えられます。",
      "似た名前のフォルダを並べて使うとき、色を変えておくと取り違えません。",
    ],
    "dir-badge-workspace": [
      "このセルが開いているフォルダの名前です。",
      "どのプロジェクトで作業させているかを、指示を出す前に確かめるときに。",
    ],
    "git-chip": [
      "git の現在地です。左からブランチ・未保存（未コミット）の変更・GitHub との差。",
      "作業前に main のまま触っていないか、作業後に保存し忘れがないかを確かめるときに。",
    ],
    "git-branch": [
      "いま作業しているブランチ（作業の枝）の名前です。",
      "本番用の main で直接作業していないかを、指示を出す前に確かめるときに。",
    ],
    "git-dirty": [
      "まだコミット（保存）していない変更の数です。",
      "作業が終わったのに数字が残っていたら、「コミットして」と頼む合図です。",
    ],
    "git-ab": [
      "GitHub との差です。↑ はこちらだけ、↓ は GitHub 側だけにある変更の数。",
      "↑ が残っていれば送り忘れ（push）、↓ があれば作業前に取り込み（pull）が要ります。",
    ],
    "model-badge": [
      "使っている AI のモデルと、会話の記憶の残り（ctx）です。",
      "ctx の残りが少なくなったら、新しいセルで話を分けると取り違えが減ります。",
    ],
    "cell-usage": [
      "このセッションでやり取りした量です。⇡ が送った分、⇣ が返ってきた分。",
      "思ったより使っているセッションを見つけて、早めに区切るときの目安に。",
    ],
    "cell-account-mark": [
      "このセルがどのアカウントで動いているかの印です。",
      "仕事用と個人用など、アカウントを使い分けているときの取り違え防止に。",
    ],
    "cell-canvas-chip": [
      "Canvas に、まだ見ていない結果が届いている数です。押すと開きます。",
      "エージェントが図や表を出したのに気づかなかった、を防ぎます。",
    ],
    "cell-wt-badge": [
      "この作業用コピーで、元からどれだけ変えたかです。押すと変更の一覧が出ます。",
      "エージェントがどのファイルを触ったか、コミット前に確かめたいときに。",
    ],
    "work-chip": [
      "このセルが取り組んでいる PR や Issue です。",
      "どのセルがどの Issue をやっているかを、並べたまま見分けたいときに。",
    ],
    "worktree-env-chip": [
      "この作業用コピーだけに割り当てた設定（ポート番号など）です。",
      "2つのセルで同時にアプリを起動しても、ぶつからないか確かめるときに。",
    ],
    "cell-prompt": [
      "いま走っている（または最後に送った）指示です。",
      "何を頼んだか忘れたときや、別のセルと見比べるときに見ます。",
    ],
    "cell-memo-edit": [
      "このセッションに覚え書きを付けます。",
      "「請求書の修正」など、何をさせている枠かを書いておくと、あとで迷いません。",
    ],
    "cell-memo-input": [
      "このセッションの覚え書きを書く欄です。",
      "セルの役割を一言で書いておくと、たくさん並べても見分けがつきます。",
    ],
    "cell-dir": [
      "このセルのフォルダです。押すと、Finder で開く・ここで新しいターミナル、などが選べます。",
      "作ったファイルを Finder で見たいときや、同じフォルダで別の作業を始めたいときに。",
    ],
    "cell-path-item": [
      "このフォルダに対する操作です。Finder・アプリ内のファイル・新しいターミナル・GitHub。",
      "コマンドを打たずに、フォルダや GitHub のページを開きたいときに。",
    ],
    "cell-ask": [
      "別のセルに話しかけます。向こうの最後の返事を持ってくる・1往復させる、ができます。",
      "調べ物をさせたセルの結果を、実装しているセルに渡したいときに。",
    ],
    "cell-exchange-stop": [
      "セル同士のやり取りを、途中で止めます。",
      "やり取りが長引いたり、違う方向に進んだと気づいたときに。",
    ],
    "mulmo-menu-btn": [
      "このフォルダにあるスライド（Mulmo の台本）を、右側の Canvas に出します。",
      "作ったスライドを、ターミナルの横で確かめたいときに。",
    ],
    // ── セルの右上のボタン ──
    "cell-canvas-btn": [
      "右側の Canvas（図・表・スライドが出る場所）を開け閉めします。",
      "エージェントが作った図や表を見たいときに。押せなければ起動画面で Canvas をオンに。",
    ],
    "cell-prompts-btn": [
      "このセッションで自分が送った指示を、一覧で出します。",
      "前に送った長い指示をもう一度使いたいときや、頼んだことを振り返るときに。",
    ],
    "cell-transcript-btn": [
      "このセッションの会話を、読みやすい形で出します。",
      "流れが速くて読めなかった返事を、あとから落ち着いて読みたいときに。",
    ],
    "cell-github-btn": [
      "GitHub の PR と Issue の一覧を、右側に出します。",
      "Issue を選んで、そのまま作業を始めさせたいときに。",
    ],
    "cell-park-btn": [
      "このセルを脇に置きます（月のボタン）。閉じるのと違い、会話も履歴も残ります。",
      "今は使わないけれど、あとで続きをやりたいセルを一旦どけたいときに。",
    ],
    "cell-model-select": [
      "このセッションで使う AI のモデルを選びます。",
      "難しい作業は賢いモデル、簡単な作業は速いモデル、と切り替えたいときに。",
    ],
    // ── 変更と片付け ──
    "cell-diff-btn": [
      "変更をまとめる3つのボタンです。左から、コミットを頼む・送る（push）・PR を作る。",
      "コマンドを打たずに GitHub まで届けたいときに。灰色なら前の段がまだです。",
    ],
    "cell-tidy-open": [
      "PR がマージされたので、この作業用コピーを片付けるか残すかを選びます。",
      "終わった作業のフォルダが溜まってきたとき、ここから消せます。",
    ],
    "cell-tidy-dismiss": [
      "片付けの提案を閉じます。この PR についてはもう聞きません。",
      "まだ同じ場所で作業を続けたいときに。",
    ],
    "issue-start": [
      "この Issue の作業を、新しいセルで始めさせます。",
      "Issue を読ませて「これをやって」と頼む手間を、1回の押しで済ませたいときに。",
    ],
    // ── リスト表示 ──
    "cockpit-row": [
      "セルの一覧（リスト表示）の1行です。押すとそのセルへ移ります。",
      "セルが多くて探しにくいとき、覚え書きや最後の指示から目当てを探せます。",
    ],
    "term-conn-status": [
      "画面とターミナルの繋がり具合です。繋がっているときは消えます。",
      "しばらく待っても disconnected のままなら、ページを再読み込みしてみてください。",
    ],
  };

  const COLLECTIONS = [
    "集めた記録の画面です。記事のネタ・健康・計画のような「1件1枚」の記録が出ます。",
    "エージェントに記録させたものを、表や一覧で見返したいときに。",
  ];
  const BLUEPRINTS = [
    "設計図の画面です。テンプレートから、アプリを段階を踏んで作ります。",
    "いきなり全部を頼まずに、手順に沿って少しずつ作らせたいときに。",
  ];
  const COMMANDS = [
    "コマンドパレットを開きます。やりたいことを名前で探して実行できます。",
    "ボタンの場所が分からない操作を、言葉で探したいときに。",
  ];
  const MOVE_LEFT = ["このセルを左へ動かします。", "よく使うセルを見やすい位置に寄せたいときに（並べ方が手動のとき）。"];
  const MOVE_RIGHT = ["このセルを右へ動かします。", "よく使うセルを見やすい位置に寄せたいときに（並べ方が手動のとき）。"];
  const FILES_PANE = [
    "このフォルダのファイルの一覧を、右側に出します。もう一度押すと閉じます。",
    "エージェントが作ったファイルを、その場で開いて確かめたいときに。",
  ];
  const TOOLS_PANE = [
    "エージェントが使った道具（コマンドやファイル操作）の記録を、右側に出します。",
    "エージェントが裏で何をしたかを確かめたいときに。",
  ];
  const FOLDER_COLLECTIONS = [
    "このフォルダのコレクション（記録）を、右側に出します。",
    "このプロジェクトの記録だけを見ながら作業したいときに。",
  ];

  // aria-label は、上流が日本語に訳しているものがある（MulmoTerminal の表示言語が
  // 日本語のとき）。中継の窓は localhost の窓と設定の置き場所が別なので、
  // ブラウザの言語に従って日本語になりやすい。**訳された名前も並べて持つ。**
  const BY_ARIA = {
    // ── 画面の上の帯 ──
    Views: [
      "画面の切り替えです。ターミナルの並び・コレクション・PR・ルーム・作業ログを行き来します。",
      "ほかの画面から、いつものターミナルの並びに戻りたいときも、ここから。",
    ],
    "Grid view": ["ターミナルを並べて見る、いつもの画面です。", "コレクションや PR の画面から戻ってくるときに。"],
    Collections: COLLECTIONS,
    "Pinned collections and feeds": [
      "よく見るコレクションやフィードを、ここに並べておけます。",
      "毎日見る記録を、1回押すだけで開きたいときに。",
    ],
    Feeds: ["決まったサイトなどから集めた新着の一覧です。", "エージェントに集めさせたニュースや更新を、まとめて読むときに。"],
    Wiki: ["このワークスペースの Wiki（書き溜めたメモ）です。", "エージェントが残した作業記録や調べた内容を、あとから読みたいときに。"],
    Accounting: ["帳簿の画面です。", "エージェントに記帳させた収支を、一覧や集計で確かめるときに。"],
    Files: ["ファイルを探して開く画面です。", "作業フォルダの中のファイルを、Finder を開かずに見たいときに。"],
    "Pull requests": [
      "自分が出している PR の一覧です。CI（自動テスト）の結果も出ます。",
      "出した PR のテストが落ちていないか、まとめて確かめたいときに。",
    ],
    Rooms: ["複数のセッションで囲む円卓です。", "1つの話題を、立場の違う何人かのエージェントに話し合わせたいときに。"],
    Blueprints: BLUEPRINTS,
    設計図: BLUEPRINTS,
    Worklog: [
      "開発の作業ログです。どのセッションが何をしたかが Wiki に溜まります。",
      "昨日どこまで進んだか、どのセルが何をしたかを振り返るときに。",
    ],
    "New terminal": [
      "新しいターミナルを立てます。どのフォルダで、どのエージェントで始めるかを選びます。",
      "別のプロジェクトの作業を、今のセルとは別に並行して始めたいときに。",
    ],
    Notifications: [
      "溜まった知らせです。エージェントが待っている・終わった・CI が落ちた、などが入ります。",
      "席を外していた間に何が起きたかを、まとめて確かめるときに。",
    ],
    "Dismiss notification": ["この知らせを消します。", "確かめ終わった知らせを片付けて、新しいものを見やすくしたいときに。"],
    "Remote host": [
      "スマホから使えるかどうかです。繋がっていれば、外出先から同じセッションを覗けます。",
      "出かける前に、スマホから続きを見られる状態か確かめるときに。",
    ],
    "Update available": [
      "MulmoTerminal の新しい版が出ています。",
      "時間のあるときに更新すると、直った不具合や新しい機能が入ります。",
    ],
    "Star MulmoTerminal on GitHub": ["GitHub で MulmoTerminal にスター（いいね）を付けます。", "気に入ったら、作っている人への応援になります。"],
    "Attention sound on": [
      "エージェントが返事を待っているとき、音で知らせます（いまオン）。",
      "ほかの作業をしながら返事待ちに気づきたいときに。静かにしたいなら押してオフに。",
    ],
    "Attention sound off": ["返事待ちを知らせる音が切れています。", "返事待ちを音で知りたくなったら、押してオンにします。"],
    "Attention sound blocked - click anywhere to enable": [
      "ブラウザが音を止めています。画面のどこかを1回押すと鳴るようになります。",
      "開き直した直後は、音が出ないことがあります。",
    ],
    "Show list roster": ["セルの一覧を、文字のリストで出します。", "セルが多くて、縮小画面では見分けにくいときに。"],
    "Show thumbnail strip": ["セルの一覧を、縮小画面の帯に戻します。", "各セルの画面を、ちらっと見比べたいときに。"],
    Commands: COMMANDS,
    コマンド: COMMANDS,
    Settings: [
      "設定です。テーマ・音・キーボード・エージェントの選び方などを変えます。",
      "文字が小さい・Enter の動きが合わない、など使い心地を直したいときに。",
    ],
    "Resize the roster": ["左の一覧の幅を変える仕切りです。つまんで動かします。", "一覧の文字が切れて読めないときに広げます。"],
    "Resize the thumbnail strip": ["縮小画面の帯の大きさを変える仕切りです。", "各セルの様子を、もっと大きく見たいときに。"],
    "Resize side pane": ["右側の欄の幅を変える仕切りです。", "Canvas やファイルを大きく見たいときに広げます。"],
    // ── セルのボタン ──
    "Move terminal left": MOVE_LEFT,
    "Move terminal right": MOVE_RIGHT,
    "Expand terminal": [
      "このセルだけを大きく開きます。右側に Canvas やファイルの欄も出せます。",
      "1つの作業にじっくり向き合いたいときに。",
    ],
    "Restore terminal": ["大きく開いたセルを、元の並びに戻します。", "ほかのセルの様子も見たくなったときに。"],
    "Start a terminal in this directory": [
      "同じフォルダで、もう1本ターミナルを立てます。",
      "1つのプロジェクトで、調べ物と実装など別々のことを並行させたいときに。",
    ],
    "Show files": FILES_PANE,
    "Hide files": FILES_PANE,
    "Show tools": TOOLS_PANE,
    "Hide tools": TOOLS_PANE,
    "Show this folder's collections": FOLDER_COLLECTIONS,
    "Hide collections": FOLDER_COLLECTIONS,
    "Close terminal": [
      "このセルを閉じます。脇に置く（月のボタン）と違い、画面から消えます。",
      "終わった作業を片付けるときに。続きをやるかもしれないなら、脇に置く方を。",
    ],
    "Close diff": ["変更の一覧を閉じます。", "確かめ終わったら閉じます。"],
    // ── 指示欄のまわり ──
    "Insert a file path": [
      "ファイルを選んで、その場所（パス）を指示欄に差し込みます。",
      "「このファイルを直して」と頼むとき、長い場所を打たずに済みます。",
    ],
    "Open this branch's PR": ["このブランチの PR を GitHub で開きます。", "PR のレビューや CI の結果を見に行きたいときに。"],
    "Start voice input": [
      "声で指示を入れます。文字になってから指示欄に入ります。",
      "長い説明を打つのが面倒なときに。送る前に文字を直せます。",
    ],
    "Stop voice input": ["声の入力を止めます。", "言い終えたら押します。"],
    "Enable voice input (downloads the speech model)": [
      "声の入力を使えるようにします。最初の1回だけ、声を文字にする部品を取ってきます。",
      "打つより話す方が楽なら、一度押しておきます。少し時間がかかります。",
    ],
    "Copy the last code block": [
      "直前の返事にあったコードの部分を、そのままコピーします。",
      "エージェントが書いた文面やコマンドを、Slack やメールに貼りたいときに。",
    ],
    "Copy the code block": ["このコードの部分をコピーします。", "返事の中の一部だけを貼りたいときに。"],
    "Show activity timeline": ["このセッションが何をしてきたかの時系列です。", "長く走らせたあとに、どこで何をしたかを追いたいときに。"],
    "Terminal input": [
      "エージェントへの指示を書くところです。",
      "送り方（Enter で送るか、Shift+Enter で送るか）は設定で変えられます。",
    ],
  };

  // 中身が変わる名前（件数・状態・相手の名前が入る）は、頭の部分で当てる。
  const BY_ARIA_PREFIX = [
    [
      "Grid cell ordering:",
      [
        "セルの並べ方です。押すたびに、手動 → 優先度順 → 自動（手が要るセルが上）と変わります。",
        "待っているセルを見落としがちなら自動に、並びを固定したいなら手動にします。",
      ],
    ],
    [
      "Grid status — ",
      [
        "動いている・待っている・終わったセルの数のまとめです。",
        "どこかのセルが返事を待っていないか、全体をさっと確かめるときに。",
      ],
    ],
    ["Collections — ", COLLECTIONS],
    [
      "Exchange one turn with ",
      [
        "選んだセルと1往復だけやり取りさせます。こちらの返事を送り、答えを持ってきます。",
        "レビュー役のセルに、今の結果を見てもらいたいときに。",
      ],
    ],
  ];

  // ── Skill メニュー（Issue #226）──────────────────────────────
  //
  // MulmoTerminal の Skill メニューは、各スキルの SKILL.md の `description` を英語の
  // ツールチップ（title）に出し、名前だけを並べる。項目に `data-testid` も `aria-label` も
  // 無いので、**メニューを開くボタンの title** で Skill メニューだと見分ける（Run の
  // メニューも同じ形の項目を持っていて、そちらの title はコマンドそのもの）。
  //
  // - 同梱スキル（MulmoTerminal が配る mulmoterminal-*）は下の表の日本語（2段）
  // - それ以外（本人やプロジェクトのスキル）は、その場の説明を1〜2文に畳んで出す
  // - 英語の説明は、中継が裏で訳した控え（/__mulmo-guide/skill-ja）があればそれを出す。
  //   無ければ原文のまま。**画面の側で訳を捏造しない**
  const SKILL_MENU_TITLE = "Run a skill in the current session";
  const SKILL_BUTTON = [
    "このフォルダで使えるスキル（決まった手順の頼み方）の一覧を開きます。",
    "選ぶと、このセルのエージェントにそのスキルを実行させます。定型の作業を頼むときに。",
  ];
  // 上流の server/skills/<名前>/SKILL.md の description を訳したもの（6.5.0）。
  const BY_SKILL = {
    "mulmoterminal-bug-report": [
      "「MulmoTerminal が変」の相談窓口です。設定や仕様かを調べ、残った不具合だけ報告します。",
      "動かない・おかしいと感じたとき、不具合を報告したいとき、動きの理由を知りたいときに。",
    ],
    "mulmoterminal-config": [
      "MulmoTerminal の設定の入口です。いまどう設定されているかも、実際に読んで答えます。",
      "何を変えられるか知りたいとき、設定が効かないときに。分野ごとのスキルへ案内もします。",
    ],
    "mulmoterminal-decisions": [
      "このプロジェクトで過去に人へ何を聞き、どう答えられたかを読み返します。",
      "似た質問をする前や、「前にも決めたよね」というときに。",
    ],
    "mulmoterminal-dirs": [
      "作業するフォルダに色・名前・並び順・文字の大きさを付け、これまでの付け方にそろえます。",
      "プロジェクトを色分けしたいとき、新しく clone したものに色が無いときに。",
    ],
    "mulmoterminal-header": [
      "セルの見出しに、自分用のボタン（ビルド・テストなど）や情報の札を足します。",
      "よく打つコマンドを1クリックにしたいとき、見出しに出したい情報があるときに。",
    ],
    "mulmoterminal-keys": [
      "キーボードのショートカットを割り当て、キー操作やコピーのおかしな動きを直します。",
      "マウスなしでセルを移りたいとき、Enter や Cmd+← が思った動きをしないときに。",
    ],
    "mulmoterminal-model": [
      "標準以外のモデル（OpenRouter・ローカルの Ollama など）でセッションを動かします。",
      "安いモデルや別のモデルを使いたいとき、モデルを変えたら動かなくなったときに。",
    ],
    "mulmoterminal-notify": [
      "どんなときに音やスマホへの通知を出すか、どの音を鳴らすかを決めます。",
      "通知がうるさい・静かすぎるとき、CI の失敗やコマンドの終わりを知りたいときに。",
    ],
    "mulmoterminal-shared-app": [
      "アンケート・申込表・予約フォームなど、何人かで使い答えを1か所に集めるアプリを作ります。",
      "ほかの人に書き込んでもらう・見てもらうものが要るとき、公開や取り下げのときに。",
    ],
    "mulmoterminal-theme": [
      "MulmoTerminal 全体の配色を自分で作り、設定のテーマ一覧に加えます。",
      "既成のテーマが暗すぎる・青すぎるとき、絵や写真・ブランドの色で作りたいときに。",
    ],
  };
  /** 畳んだ説明の長さの上限。吹き出し（幅 300px）で5行ほど。 */
  const MAX_FOLD = 120;

  /** 説明を1〜2文に畳む。1文目だけで長すぎれば、切って「…」を付ける。 */
  function foldDescription(text) {
    const flat = String(text ?? "").replace(/\s+/g, " ").trim();
    if (flat === "") return "";
    // 文の終わりは「。！？」の後ろ、または「. ! ?」の後ろに空白が来たところ。
    // config.json や v1.2 の点では切らない。
    const sentences = flat.split(/(?<=[。！？])|(?<=[.!?])\s+/).map((one) => one.trim()).filter(Boolean);
    let out = sentences[0] ?? flat;
    const second = sentences[1];
    if (second !== undefined) {
      const joined = /[。！？]$/.test(out) ? out + second : `${out} ${second}`;
      if ([...joined].length <= MAX_FOLD) out = joined;
    }
    return [...out].length > MAX_FOLD ? `${[...out].slice(0, MAX_FOLD - 1).join("")}…` : out;
  }

  /**
   * Skill メニューの1項目に出す説明。[何をするか, どんな時に使うか]。2段目が空なら1段で出す。
   * translations は中継の控え（原文 → 訳）。
   */
  function skillText(slug, description, translations) {
    if (Object.hasOwn(BY_SKILL, slug)) return BY_SKILL[slug];
    if (typeof description !== "string" || description.trim() === "") return null;
    const ja = translations !== null && typeof translations === "object" && Object.hasOwn(translations, description)
      ? translations[description]
      : null;
    return [foldDescription(typeof ja === "string" ? ja : description), ""];
  }

  // 検査（tests/guide-text-test.mjs）から読むための口。ブラウザでは使わない。
  if (typeof document === "undefined") {
    globalThis.mulmoGuideTables = {
      BY_TESTID, BY_ARIA, BY_ARIA_PREFIX, BY_SKILL, SKILL_BUTTON, SKILL_MENU_TITLE, MAX_FOLD,
      foldDescription, skillText,
    };
    return;
  }

  // Mulmo Control が立てる極小サーバー（Sources/GuideServer.swift）。
  // **ここのポートは check.sh が GuideServer.port と突き合わせている。**
  // 片方だけ変えると、画面は黙って出なくなるだけで誰も気づけない。
  const ENDPOINT = "http://127.0.0.1:34599/mt-guide";
  const POLL_MS = 5000;
  const STORE_KEY = "mt-hover-guide-on";
  /** 印を探して親へ辿る上限。印の無い飾りの中にいても、ボタンまでは届く深さ。 */
  const MAX_DEPTH = 8;

  // MulmoTerminal のポートは動く（既定のポート、`.env` の PORT、逃げた先…）。
  // だから **ポートでは判定しない。** 画面が自分で名乗っている印で決める。
  const isMulmoTerminal = () =>
    document.title === "mulmoterminal" ||
    document.querySelector('[data-testid="cell-header-main"], [data-testid="mulmo-menu-btn"]') !== null;

  // 説明が付く印を持たない要素にも、上流が英語の説明を持たせていることがある。
  // その場合は**英語をそのまま残す**。訳が無いことと、訳を捏造することは違う。

  // ── 状態 ────────────────────────────────────────────────────
  //
  // 既定は ON。Mulmo Control 側の既定（UserDefaults 未設定 = ON）と揃える。
  // 揃っていないと、アプリを入れた瞬間に画面が変わったように見える。
  let on = localStorage.getItem(STORE_KEY) !== "0";
  let bubble = null;
  /** 吹き出しを出しているあいだ、英語のツールチップを預かっている要素。 */
  let muted = null;

  const save = () => localStorage.setItem(STORE_KEY, on ? "1" : "0");

  /** Mulmo Control に従う。居なければ（繋がらなければ）自分の記憶で動く。 */
  async function follow() {
    try {
      const res = await fetch(ENDPOINT, { cache: "no-store" });
      if (!res.ok) return;
      const body = await res.json();
      if (typeof body.on === "boolean" && body.on !== on) {
        on = body.on;
        save();
        paint();
        if (!on) hide();
      }
    } catch {
      // アプリが止まっているだけ。単体で動き続ける。
    }
  }

  // ── 吹き出し ────────────────────────────────────────────────
  //
  // 2段になったぶん背が伸びるので、幅は画面に合わせて縮め、長い英単語やパスでも
  // 折り返す（Issue #224）。
  function ensureBubble() {
    if (bubble !== null) return bubble;
    bubble = document.createElement("div");
    bubble.id = "mtg-bubble";
    bubble.style.cssText = [
      "position:fixed",
      "z-index:2147483646",
      "box-sizing:border-box",
      "width:max-content",
      "max-width:min(300px, calc(100vw - 16px))",
      "padding:9px 11px",
      "border-radius:8px",
      "background:rgba(17,17,20,0.96)",
      "color:#f2f2f5",
      "font:12.5px/1.6 -apple-system,BlinkMacSystemFont,'Hiragino Sans',sans-serif",
      "white-space:normal",
      "overflow-wrap:anywhere",
      "line-break:strict",
      "box-shadow:0 6px 24px rgba(0,0,0,0.35)",
      "pointer-events:none",
      "display:none",
    ].join(";");
    const what = document.createElement("div");
    what.dataset.part = "what";
    what.style.cssText = "font-weight:600";
    const when = document.createElement("div");
    when.dataset.part = "when";
    when.style.cssText = "margin-top:5px;padding-top:5px;border-top:1px solid rgba(255,255,255,0.14);color:#c9c9d1";
    bubble.append(what, when);
    document.body.appendChild(bubble);
    return bubble;
  }

  /** 1つの要素の印から説明を引く。無ければ null。 */
  function lookup(node) {
    const byId = BY_TESTID[node.getAttribute("data-testid") ?? ""];
    if (byId !== undefined) return byId;
    const aria = node.getAttribute("aria-label");
    if (aria === null) return null;
    if (Object.hasOwn(BY_ARIA, aria)) return BY_ARIA[aria];
    const hit = BY_ARIA_PREFIX.find(([prefix]) => aria.startsWith(prefix));
    return hit === undefined ? null : hit[1];
  }

  // ── Skill メニューを見分ける ────────────────────────────────

  /** title を読む。吹き出しを出しているあいだは預かっているので、そちらも見る。 */
  const titleOf = (node) => node.getAttribute("title") ?? node.dataset.mtgTitle ?? null;

  /** Skill メニューを開くボタンか。 */
  const isSkillButton = (node) =>
    node instanceof HTMLButtonElement &&
    node.getAttribute("aria-haspopup") === "menu" &&
    titleOf(node) === SKILL_MENU_TITLE;

  /** 項目の名前。アイコンは別の要素なので、項目じかの文字だけをつなぐ。 */
  const slugOf = (item) =>
    [...item.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE).map((n) => n.textContent).join("").trim();

  /** 中継が訳した控え。古ければ裏で取り直す（待たない。次に動かしたときに出る）。 */
  const SKILL_JA_PATH = "/__mulmo-guide/skill-ja";
  const SKILL_JA_TTL_MS = 5000;
  let skillJa = null;
  let skillJaAt = 0;
  function refreshSkillJa() {
    if (Date.now() - skillJaAt < SKILL_JA_TTL_MS) return;
    skillJaAt = Date.now();
    fetch(SKILL_JA_PATH, { cache: "no-store" })
      .then((res) => (res.ok ? res.json() : null))
      .then((body) => {
        if (body !== null && typeof body.translations === "object") skillJa = body.translations;
      })
      .catch(() => {
        // 中継が古い・訳が無い。原文のまま出す。
      });
  }

  /** Skill メニュー（ボタンと項目）の説明。当てはまらなければ null。 */
  function explainSkill(el) {
    const button = el.closest("button");
    if (button !== null && isSkillButton(button)) return SKILL_BUTTON;
    const item = el.closest('[role="menuitem"]');
    const menu = item?.closest('[role="menu"]');
    const opener = menu?.previousElementSibling;
    if (item == null || opener == null || !isSkillButton(opener)) return null;
    refreshSkillJa();
    return skillText(slugOf(item), titleOf(item), skillJa);
  }

  /** その要素に当てる説明。**知らない印で止まらず、親へ辿る**（アイコンの中にいても届く）。 */
  function explain(el) {
    const skill = explainSkill(el);
    if (skill !== null) return skill;
    let node = el.closest("[data-testid],[aria-label]");
    for (let depth = 0; node !== null && depth < MAX_DEPTH; depth += 1) {
      const text = lookup(node);
      if (text !== null) return text;
      node = node.parentElement?.closest("[data-testid],[aria-label]") ?? null;
    }
    return null;
  }

  // 英語のツールチップ（title）を、吹き出しを出しているあいだだけ預かる。
  // 両方出ると、英語の方が上に重なって日本語が読めない（報告のスクリーンショットがそれ）。
  function mute(el) {
    const holder = el.closest("[title]");
    if (holder === muted) return;
    unmute();
    if (holder === null) return;
    holder.dataset.mtgTitle = holder.getAttribute("title") ?? "";
    holder.removeAttribute("title");
    muted = holder;
  }

  function unmute() {
    if (muted === null) return;
    // 預かっている間に画面側が付け直していたら、そちらを残す。
    if (!muted.hasAttribute("title")) muted.setAttribute("title", muted.dataset.mtgTitle ?? "");
    delete muted.dataset.mtgTitle;
    muted = null;
  }

  function show([what, when], x, y) {
    const box = ensureBubble();
    box.querySelector('[data-part="what"]').textContent = what;
    const whenPart = box.querySelector('[data-part="when"]');
    whenPart.textContent = when;
    // 本人やプロジェクトのスキルは説明が1つだけ。空の2段目で線だけ出さない。
    whenPart.style.display = when === "" ? "none" : "block";
    box.style.display = "block";
    // 画面の外へはみ出さない。右端と下端で折り返す。
    const rect = box.getBoundingClientRect();
    const left = Math.min(x + 14, window.innerWidth - rect.width - 8);
    const top = y + rect.height + 24 > window.innerHeight ? y - rect.height - 12 : y + 18;
    box.style.left = `${Math.max(8, left)}px`;
    box.style.top = `${Math.max(8, top)}px`;
  }

  const hide = () => {
    if (bubble !== null) bubble.style.display = "none";
    unmute();
  };

  function onMove(event) {
    if (!on) return;
    const target = event.target instanceof Element ? event.target : null;
    const text = target === null ? null : explain(target);
    if (text === null) {
      hide();
      return;
    }
    mute(target);
    show(text, event.clientX, event.clientY);
  }

  // ── 「?」ボタン ─────────────────────────────────────────────
  //
  // Mulmo Control を入れていない人でも切れるように、画面側にも口を残す。
  function mountToggle() {
    const button = document.createElement("button");
    button.id = "mtg-toggle";
    button.type = "button";
    button.textContent = "?";
    button.style.cssText = [
      "position:fixed",
      "right:14px",
      "bottom:14px",
      "z-index:2147483647",
      "width:28px",
      "height:28px",
      "border-radius:50%",
      "border:none",
      "cursor:pointer",
      "font:600 14px/1 -apple-system,sans-serif",
    ].join(";");
    button.addEventListener("click", () => {
      on = !on;
      save();
      paint();
      if (!on) hide();
    });
    document.body.appendChild(button);
    return button;
  }

  function paint() {
    const button = document.getElementById("mtg-toggle");
    if (button === null) return;
    button.style.background = on ? "#2f7df6" : "rgba(120,120,128,0.35)";
    button.style.color = on ? "#fff" : "#d8d8dd";
    button.title = on ? "画面ガイド: オン（押すと切る）" : "画面ガイド: オフ（押すと出す）";
  }

  function start() {
    if (!isMulmoTerminal()) return;
    mountToggle();
    paint();
    document.addEventListener("mousemove", onMove, { passive: true });
    document.addEventListener("mouseleave", hide, { passive: true });
    void follow();
    setInterval(follow, POLL_MS);
    // 別のウィンドウで切り替えたときに、戻ってきた瞬間に追いつく。
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) void follow();
    });
  }

  // 画面ができるまで待つ（SPA なので、最初の描画は空のことがある）。
  if (isMulmoTerminal()) start();
  else setTimeout(start, 1500);
})();
