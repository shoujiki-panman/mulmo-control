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
    // 鍵を預かっていれば、MulmoClaude が止まっていても繋げる（Issue #145）。
    // 「繋ぎ直す」と分けているのは、押したときに起動まで走るのがこちらだけだから。
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
    /// Mulmo Control が Keychain に鍵を預かっているか（Issue #145）。
    ///
    /// Optional なのは、MulmoTerminal 側の書き置きにこの項目が無いから。
    /// 非 Optional にすると、項目が1つ足りないだけで復号ごと失敗し、画面が
    /// 「未確認」に落ちる（SelfUpdateStatus で一度踏んだ形）。古い版が書いた
    /// MulmoClaude 側の書き置きにも無いので、更新直後も同じことが起きる。
    let hasStash: Bool?

    var isOffline: Bool { state == "offline" }

    /// MulmoClaude が止まっていても、預かった鍵で繋げる状態か。
    var canConnectFromControl: Bool { hasStash == true }
}

/// 登録したプロジェクトと、そのディレクトリで動いているリモートセッション
/// （Issue #152）。スマホから使うので、**セッション名がそのまま向こうで
/// 探す手がかりになる**。だから状態だけでなく名前を出す。
///
/// 状態は自前で持たない。`claude agents --json` が cwd 付きで返すものを
/// 毎回読み直している。pid を覚えないので、アプリを再起動しても戻る。
struct ProjectSession: Decodable {
    let name: String
    let path: String
    /// 登録したディレクトリが実在するか。消したあとも登録は残る。
    let exists: Bool
    /// claude 側がこのディレクトリの信頼確認を通しているか。通っていないと
    /// 初回起動で確認が出て止まるので、押す前に伝える必要がある。
    let trusted: Bool
    let autoStart: Bool
    /// 動いているセッションの名前。止まっているときは空。
    let sessionName: String
    let sessionCount: Int
    /// busy / idle / running / stopped
    let status: String

    var isRunning: Bool { status != "stopped" }
}

/// プロジェクトの行に出す説明。
///
/// 「停止中」と「フォルダが無い」を混ぜないこと。起動を押せば直るのは前者
/// だけで、後者は登録し直すしかない（#23 で「切れた」と「繋いでいない」を
/// 混ぜて時間を使ったのと同じ形）。
func projectSessionDetail(_ project: ProjectSession) -> String {
    if !project.exists { return "フォルダが見つかりません" }
    if !project.isRunning {
        return project.trusted ? "停止中" : "停止中・初回は確認が要ります"
    }
    let label = project.sessionName.isEmpty ? "セッション" : project.sessionName
    if project.sessionCount > 1 { return "\(label) ほか\(project.sessionCount - 1)件" }
    return label
}

/// 行の左の印を緑にしてよいか。動いていて、かつ実在するときだけ。
func projectSessionOK(_ project: ProjectSession) -> Bool {
    project.exists && project.isRunning
}
