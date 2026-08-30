// スマホ連携の「状態 → 画面に出す言葉」の対応。
//
// main.swift から分けてあるのは、**検査から動かすため**（Issue #149）。
// check.sh はこのファイルだけを swiftc に渡してテストを組み、12通りの
// 対応表と突き合わせる。アプリと検査が同じ1本を読むので、写しがずれる
// 形にはならない。
//
// ここには外の世界に触るものを置かないこと。ファイルも通信も画面も
// 使わない、状態だけで決まるものだけ。触れた瞬間、検査から動かせなくなる。

/// スマホ連携の2行に出すボタンの文字。状態が同じなら同じ言葉が出るように、
/// 1か所で決める。以前は同じ `never`（まだ繋いでいません）に対して、片方が
/// 「繋ぎ方を見る」、もう片方が「設定を開く」と並んでいた。押したときの動きは
/// どちらも「アプリを開く（止まっていれば起動してから）」で同じ。
func remoteHostButtonTitle(_ status: RemoteHostStatus) -> String? {
    if status.state == "online" { return nil }
    if status.isOffline { return "繋ぎ直す" }
    // 鍵を預かっていれば、本体が止まっていても繋げる（Issue #145 / #154）。
    // 「繋ぎ直す」と分けているのは、押したときに起動まで走るのがこちらだから。
    // 2行とも同じ形になったので、ここも2行で共通のまま。
    if status.canConnectFromControl { return "繋ぐ" }
    return "設定を開く"
}

/// スマホ連携（RemoteHost）の状態。切れても MulmoTerminal は動き続けるので、
/// 放っておくと気づけない。never = 一度も繋いでいない（再接続する先が無い）。
struct RemoteHostStatus: Decodable {
    let checkedAt: String
    let state: String   // online / offline / never / unknown
    let hasSession: Bool
    let detail: String
    /// Mulmo Control が Keychain に鍵を預かっているか（Issue #145 / #154）。
    ///
    /// Optional のままにしてある。2行とも書くようになったが、**更新した直後は
    /// 古い版が書いた書き置きが残っている**。非 Optional にすると、項目が1つ
    /// 足りないだけで復号ごと失敗し、画面が「未確認」に落ちる
    /// （SelfUpdateStatus で一度踏んだ形）。
    let hasStash: Bool?

    var isOffline: Bool { state == "offline" }

    /// MulmoClaude が止まっていても、預かった鍵で繋げる状態か。
    var canConnectFromControl: Bool { hasStash == true }
}

/// 登録したプロジェクトと、そこに立てたリモートセッション（Issue #152）。
///
/// スマホから使うので、**セッション名がそのまま向こうで探す手がかり**になる。
///
/// 「繋がっている」と言ってよいのは Mulmo Control が立てたものが生きている
/// ときだけ。同じフォルダで人が手で開いたセッションを数えると、止めたのに
/// 「動作中」と出る（実測でそうなった）。
struct ProjectSession: Decodable {
    let name: String
    let path: String
    /// 登録したディレクトリが実在するか。消したあとも登録は残る。
    let exists: Bool
    /// claude 側がこのディレクトリの信頼確認を通しているか。通っていないと
    /// 初回にターミナルが開いて人が答えることになるので、押す前に伝える。
    let trusted: Bool
    let autoStart: Bool
    /// running / stopped
    let status: String

    var isRunning: Bool { status == "running" }
}

/// プロジェクトの行に出す説明。
///
/// 「停止中」と「フォルダが無い」を混ぜないこと。押せば直るのは前者だけで、
/// 後者は登録し直すしかない（#23 で「切れた」と「繋いでいない」を混ぜて
/// 時間を使ったのと同じ形）。
///
/// 動いているときは「スマホから使えます」。**環境タブのスマホ連携の行と同じ
/// 言葉にする**（Issue #158）。以前はセッション名を出していたが、その名前は
/// 常にタイトルと同じ文字列で、「mulmoclaude / mulmoclaude」と2回書いている
/// だけだった。同じ状態には同じ言葉、はこのファイルの決めごとでもある。
func projectSessionDetail(_ project: ProjectSession) -> String {
    if !project.exists { return "フォルダが見つかりません" }
    if !project.isRunning {
        return project.trusted ? "停止中" : "停止中・初回は確認が要ります"
    }
    return "スマホから使えます"
}

/// 行に出すボタンの文字。フォルダが無いときは押す先が無いので出さない。
func projectButtonTitle(_ project: ProjectSession) -> String? {
    if !project.exists { return nil }
    return project.isRunning ? "止める" : "繋ぐ"
}

/// 行の左の印を緑にしてよいか。動いていて、かつ実在するときだけ。
func projectSessionOK(_ project: ProjectSession) -> Bool {
    project.exists && project.isRunning
}
