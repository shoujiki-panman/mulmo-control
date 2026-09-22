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
    /// online / taken / offline / untrusted / error / no-cli / no-dir / halted
    ///
    /// taken = 別のアプリが枠を取っている（Issue #164）。繋がってはいるので
    /// 使えるが、こちらから繋ぐ先は無い。
    ///
    /// halted = 何度も落ちたので、自動の繋ぎ直しを止めた（Issue #212）。
    /// Claude Code 側だけ。「繋ぐ」を押せば再開する。
    let state: String
    /// 画面に出す説明。作るのはスクリプト側（スマホ連携の2行と同じやり方）。
    let detail: String
    /// Claude Code 側だけ。`https://claude.ai/code/session_…`
    let url: String?
    /// Codex 側だけ。短命なペアリングコード。
    let pairCode: String?
    /// Claude Code 側だけ（Issue #212）。「繋いでおきたい」と言われているか。
    /// 押したのは人で、止めるまで Mulmo Control が立て直し続ける。
    var want: Bool? = nil
    /// 自動の繋ぎ直しで最後に起きたこと。restored（落ちたので繋ぎ直した）/
    /// started（控えが無いところから繋いだ）/ failed（立ち上がらなかった）/
    /// halted（何度も落ちたので止めた）/ 空。
    var event: String? = nil
    /// その時刻（`9/23 14:05`）。書くのはスクリプト側。
    var eventAt: String? = nil

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

/// Codex の行に出すボタンの文字（Issue #166）。
///
/// Codex に入口の URL は無い。代わりに、繋いだあとはペアリングコードを出す口が
/// 要る。**枠が埋まっているとき（taken）は出さない。** コードを出すのは
/// こちらのデーモンで、そのとき動いているのは別のアプリだから、押しても
/// 「先に繋いでください」になる（実際になった）。
///
/// ここに置いてあるのは、**画面側で分岐を足すと対応表を通らないから**。
/// 一度そうして、押すと必ず失敗するボタンを出した。
func codexButtonTitle(_ status: AgentRemote) -> String? {
    if status.state == "online" { return "コード" }
    return agentRemoteButtonTitle(status)
}

/// 止める口を出してよいか。動いているものにしか出さない。
///
/// halted（自動の繋ぎ直しを止めた）にも出す。動いてはいないが、**「繋いで
/// おきたい」はまだ覚えている**ので、それを取り下げる口が要る（Issue #212）。
func agentRemoteCanStop(_ status: AgentRemote) -> Bool {
    status.state == "online" || status.state == "error" || status.state == "halted"
}

/// Claude Code の行の下に出す知らせ（Issue #212）。
///
/// 自動で繋ぎ直したことは、**言わなければ誰にも分からない**。スマホから
/// 繋がっているように見えても、それが1時間前に落ちて立て直した2本目なのか、
/// ずっと同じ1本なのかは、画面に出さない限り区別がつかない。
///
/// 行の説明は12文字まで（131）なので、ここは行の下に別に出す。
/// 「繋いでおきたい」と言われていないときは何も出さない（止めた人に、
/// 止めたものの話をしない）。
func claudeRemoteNotes(_ status: AgentRemote, launchAtLogin: Bool) -> [String] {
    guard status.want == true else { return [] }
    var notes: [String] = []
    let at = status.eventAt ?? ""
    switch status.event ?? "" {
    case "restored":
        notes.append("落ちたので \(at) に繋ぎ直しました")
    case "started":
        notes.append("\(at) に自動で繋ぎました")
    case "failed":
        notes.append("\(at) に繋ぎ直そうとしましたが、立ち上がりませんでした")
    case "halted":
        notes.append("何度も落ちるので、自動の繋ぎ直しを止めました（\(at)）。「繋ぐ」で再開します")
    default:
        break
    }
    // 信頼確認は人が踏むもの。自動では踏まないので、踏むまで戻らないと言う。
    if status.state == "untrusted" {
        notes.append("初回の確認が済むまで、自動では繋ぎ直しません")
    }
    // 再起動のあと立て直すのは Mulmo Control 自身。ログイン時に起動して
    // いなければ、立て直す者が居ない。
    if !launchAtLogin {
        notes.append("Mac を再起動すると切れたままになります。戻すには上の「Mulmo Control を自動で起動」をオンに")
    }
    return notes
}

/// 使える状態か。`taken` は他所が繋いでいるが、スマホからは使える。

/// 行の左の印を緑にしてよいか。エラーは緑にしない（動いてはいるが使えない）。
func agentRemoteOK(_ status: AgentRemote) -> Bool {
    status.state == "online" || status.state == "taken"
}

/// 「前回の更新」の記録を、行に収まる1行へ畳んだもの（Issue #183）。
///
/// `hasDetail` が false のときは開いても同じものしか出ない。押せる形にすると、
/// 押して何も起きない行になる。
struct LastUpdateDigest {
    let headline: String
    let hasDetail: Bool
}

/// 更新の記録は、版の行・更新されなかったものとその理由・上流の新機能の箇条書き
/// まで入るので、長いときは20行を超える。そのままパネルに置くと画面の下から
/// はみ出して、一番下の「終了」に手が届かなくなる（#192 と同じ壊れ方）。
///
/// **中身は減らさない。** 何が動いて何が動かなかったかは、あとから理由を辿る
/// ための記録（#104）。減らすのではなく、あらましだけ行に出して、実物は押した
/// ときに開く。
///
/// 数えられないときは、作った言葉を出さずに**書いてある最初の1行をそのまま**
/// 出す。記録の形が変わったときに、嘘の要約を出すよりは素の文字のほうがいい。
func lastUpdateDigest(_ report: String) -> LastUpdateDigest {
    let lines = report
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(squeezed)
        .filter { !$0.isEmpty }
    guard let first = lines.first, first != "まだありません" else {
        return LastUpdateDigest(headline: "まだありません", hasDetail: false)
    }
    let stamp = isTimeStamp(first) ? first : ""
    let body = Array(lines.dropFirst(stamp.isEmpty ? 0 : 1))
    // 版の行が並ぶのは、上流の新機能（更新の内容）と据え置き（更新されなかった
    // もの）が始まるまで。箇条書きにも矢印が入ることがあるので、そこで区切る。
    let versionLines = body.prefix(while: { !$0.hasPrefix("更新の内容") && !$0.hasPrefix("更新されなかったもの") })
    let moved = versionLines.filter { $0.contains(" → ") }.count
    let stalled = body.drop(while: { !$0.hasPrefix("更新されなかったもの") })
        .dropFirst()
        .prefix(while: { !$0.hasPrefix("更新の内容") && !$0.hasPrefix("ログ: ") })
        .count
    // 1件だけ動いた日は、数より**その行**のほうが言えることが多い
    // （「1件を更新」より「MulmoClaude: 1.18.0 → 1.19.0」）。Issue #205。
    let only = moved == 1 && stalled == 0 ? versionLines.first(where: { $0.contains(" → ") }) : nil
    return LastUpdateDigest(
        headline: only.map { stamp.isEmpty ? $0 : "\(stamp) ・ \($0)" }
            ?? headline(stamp: stamp, moved: moved, stalled: stalled, fallback: body.first ?? first),
        hasDetail: lines.count > 1
    )
}

/// 何件動いて何件そのままだったか。数が取れないときは1行目を返す。
private func headline(stamp: String, moved: Int, stalled: Int, fallback: String) -> String {
    let counted: String
    switch (moved, stalled) {
    case (0, 0):
        // 数えられなかった。作らずに、書いてあるものを出す。
        counted = fallback
    case (let m, 0):
        counted = "\(m)件を更新"
    case (0, let s):
        counted = "\(s)件そのまま"
    case (let m, let s):
        counted = "\(m)件を更新 / \(s)件そのまま"
    }
    return stamp.isEmpty ? counted : "\(stamp) ・ \(counted)"
}

/// 前後の空白を落とす。Foundation を呼ばずに済ませる（この1本は外の世界に
/// 触らない約束で、検査から直に動かしている）。
private func squeezed(_ value: Substring) -> String {
    var slice = value
    while let head = slice.first, head.isWhitespace { slice = slice.dropFirst() }
    while let tail = slice.last, tail.isWhitespace { slice = slice.dropLast() }
    return String(slice)
}

/// 記録の1行目に入る `9/15 22:06`。日付が無い記録もあるので、形で見分ける。
private func isTimeStamp(_ line: String) -> Bool {
    let parts = line.split(separator: " ")
    guard parts.count == 2 else { return false }
    let day = parts[0].split(separator: "/")
    let time = parts[1].split(separator: ":")
    guard day.count == 2, time.count == 2 else { return false }
    return (day + time).allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
}
