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

/// エージェントのスマホ連携（Claude Code / Codex）の状態（Issue #160）。
///
/// 2つは形が違う。Claude Code は **セッション1つ＝フォルダ1つ**で、立てると
/// 入口の URL が出る。Codex は **Mac に1つのデーモン**で、URL は無く、代わりに
/// ペアリングコードで端末を繋ぐ。違うのはそこだけなので、状態は1つの形で持つ。
struct AgentRemote: Decodable {
    /// online / taken / offline / untrusted / error / no-cli / no-dir
    ///
    /// taken = 別のアプリが枠を取っている（Issue #164）。繋がってはいるので
    /// 使えるが、こちらから繋ぐ先は無い。
    let state: String
    /// 画面に出す説明。作るのはスクリプト側（スマホ連携の2行と同じやり方）。
    let detail: String
    /// Claude Code 側だけ。`https://claude.ai/code/session_…`
    let url: String?
    /// Codex 側だけ。短命なペアリングコード。
    let pairCode: String?

    /// Optional にしてあるのは、片方にしか無い項目だから。非 Optional にすると
    /// 項目が1つ足りないだけで復号ごと失敗し、画面が「未確認」に落ちる。
    var openURL: String { url ?? "" }
    var code: String { pairCode ?? "" }
}

/// 行に出すボタンの文字。
///
/// 繋がっているときに出すのは「開く」。**入口を示せないなら押す先が無いので
/// 何も出さない。** #152 では「スマホから使えます」と言うだけで開く先を教えて
/// おらず、繋がったのに使えなかった。
func agentRemoteButtonTitle(_ status: AgentRemote) -> String? {
    if status.state == "no-cli" || status.state == "no-dir" { return nil }
    // 枠が埋まっているときは、押しても弾かれるだけ（#164 で1時間に79回弾かれた）
    if status.state == "taken" { return nil }
    if status.state == "online" { return status.openURL.isEmpty ? nil : "開く" }
    return "繋ぐ"
}

/// 止める口を出してよいか。動いているものにしか出さない。
func agentRemoteCanStop(_ status: AgentRemote) -> Bool {
    status.state == "online" || status.state == "error"
}

/// 使える状態か。`taken` は他所が繋いでいるが、スマホからは使える。

/// 行の左の印を緑にしてよいか。エラーは緑にしない（動いてはいるが使えない）。
func agentRemoteOK(_ status: AgentRemote) -> Bool {
    status.state == "online" || status.state == "taken"
}
