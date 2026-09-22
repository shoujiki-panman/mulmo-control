// スマホ連携の行に出すボタンの文字を、状態の全組み合わせで確かめる（Issue #149）。
//
// check.sh がこのファイルと Sources/StatusDisplay.swift を swiftc に渡して
// 組み、実際に走らせる。**アプリと同じ1本を読む。** 期待値をここに写して
// 持つのではなく、状態を入れて出てきた言葉を見る。
//
// 直近5件の不具合のうち4件が「アプリが世界の状態について嘘をつく」形だった。
// 検査が main.swift を grep するだけで一度も動かしていなかったので、
// 嘘が出ても誰も気づけなかった。

import Foundation

/// 状態と、そのとき出るべき言葉。nil は「ボタンを出さない」。
private struct Case {
    let state: String
    let hasStash: Bool?
    let expected: String?
}

/// state（online / offline / never / unknown）× hasStash（true / false / 無し）
/// の12通り。**1つも欠けさせないこと。** 欠けた組み合わせがそのまま穴になる。
private let cases: [Case] = [
    // 繋がっているときは、何も出さない。押す用事が無い。
    Case(state: "online",  hasStash: true,  expected: nil),
    Case(state: "online",  hasStash: false, expected: nil),
    Case(state: "online",  hasStash: nil,   expected: nil),

    // 切れているときは、控えの有無によらず繋ぎ直せる。動いているプロセスが
    // blob を持っているため。
    Case(state: "offline", hasStash: true,  expected: "繋ぎ直す"),
    Case(state: "offline", hasStash: false, expected: "繋ぎ直す"),
    Case(state: "offline", hasStash: nil,   expected: "繋ぎ直す"),

    // never = 一度も繋いでいない。本来は控えも無いはずだが、あるなら繋げる
    // （控えが残っていて状態だけ never に見えている場合。押せば直る）。
    Case(state: "never",   hasStash: true,  expected: "繋ぐ"),
    Case(state: "never",   hasStash: false, expected: "設定を開く"),
    Case(state: "never",   hasStash: nil,   expected: "設定を開く"),

    // unknown = MulmoClaude が止まっていて状態を読めない。ここで「繋ぐ」が
    // 出せることが #145 の中身。hasStash が無い（＝ MulmoTerminal 側の
    // 書き置き、または古い版が書いたもの）ときは案内に倒す。
    Case(state: "unknown", hasStash: true,  expected: "繋ぐ"),
    Case(state: "unknown", hasStash: false, expected: "設定を開く"),
    Case(state: "unknown", hasStash: nil,   expected: "設定を開く"),
]

private func show(_ value: String?) -> String { value ?? "（ボタンを出さない）" }

private func stash(_ value: Bool?) -> String {
    guard let value else { return "無し" }
    return value ? "true" : "false"
}

/// 表から行が消えても気づけるように、軸から組み合わせを組み立てて突き合わせる。
/// 期待値だけを消す壊し方は、表を数えるだけでは見つからない。
private let states = ["online", "offline", "never", "unknown"]
private let stashes: [Bool?] = [true, false, nil]

/// プロジェクトの行（Issue #152）。判断に効く入力は3つ:
/// 実在するか / 動いているか / 信頼済みか。2×2×2 = 8通りを全部並べる。
private struct AgentCase {
    let state: String
    let hasURL: Bool
    let expectedButton: String?
    let expectedCodexButton: String?
    let expectedOK: Bool
    let expectedCanStop: Bool
}

/// 状態 × 入口の有無。表を手で並べず、軸から組み立てる。1行消すと落ちる。
private func agentCases() -> [AgentCase] {
    var built: [AgentCase] = []
    // halted = 何度も落ちたので自動の繋ぎ直しを止めた（Issue #212）
    // crashed = 落ちて、次の自動の繋ぎ直しを待っている（Issue #212 / 177）
    for state in ["online", "taken", "offline", "untrusted", "error", "no-cli", "no-dir", "halted", "crashed"] {
        for hasURL in [true, false] {
            let button: String?
            // taken = 別のアプリが枠を取っている。押しても弾かれるだけなので出さない
            if state == "no-cli" || state == "no-dir" || state == "taken" {
                button = nil
            } else if state == "online" {
                // 入口を示せないなら押す先が無い（#152 で実際に無かった）
                button = hasURL ? "開く" : nil
            } else {
                button = "繋ぐ"
            }
            // Codex に入口の URL は無い。繋がっているときだけコードの口を出す
            let codexButton: String? = state == "online" ? "コード" : button
            built.append(AgentCase(
                state: state, hasURL: hasURL, expectedButton: button,
                expectedCodexButton: codexButton,
                expectedOK: state == "online" || state == "taken",
                // halted / crashed は動いていないが「繋いでおきたい」を覚えている。
                // 取り下げる口が無いと、止まった表示のまま消せない。
                expectedCanStop: ["online", "error", "halted", "crashed"].contains(state)
            ))
        }
    }
    return built
}


/// Claude Code の行の下に出す知らせ（Issue #212）。
///
/// 判断に効く入力は4つ: 繋いでおきたいか / 最後に起きたこと / 状態（未信頼か）/
/// ログイン時に起動するか。意味のある組み合わせを並べる。
private struct NoteCase {
    let title: String
    let state: String
    let want: Bool?
    let event: String?
    let launchAtLogin: Bool
    let expected: [String]
}

private let loginHint = "Mac を再起動すると切れたままになります。戻すには上の「Mulmo Control を自動で起動」をオンに"

private let noteCases: [NoteCase] = [
    NoteCase(title: "止めた人には何も言わない（落ちた記録が残っていても）",
             state: "offline", want: false, event: "restored", launchAtLogin: false, expected: []),
    NoteCase(title: "古い版が書いた控え（want が無い）には何も言わない",
             state: "online", want: nil, event: nil, launchAtLogin: false, expected: []),
    NoteCase(title: "繋いだまま何も起きていない",
             state: "online", want: true, event: "", launchAtLogin: true, expected: []),
    NoteCase(title: "落ちたので繋ぎ直した",
             state: "online", want: true, event: "restored", launchAtLogin: true,
             expected: ["落ちたので 9/23 14:05 に繋ぎ直しました"]),
    NoteCase(title: "控えが無いところから自動で繋いだ",
             state: "online", want: true, event: "started", launchAtLogin: true,
             expected: ["9/23 14:05 に自動で繋ぎました"]),
    NoteCase(title: "繋ぎ直そうとしたが立たなかった",
             state: "offline", want: true, event: "failed", launchAtLogin: true,
             expected: ["9/23 14:05 に繋ぎ直そうとしましたが、立ち上がりませんでした"]),
    NoteCase(title: "何度も落ちたので止めた",
             state: "halted", want: true, event: "halted", launchAtLogin: true,
             expected: ["何度も落ちるので、自動の繋ぎ直しを止めました（9/23 14:05）。「繋ぐ」で再開します"]),
    NoteCase(title: "落ちて繋ぎ直し待ち（前回の「繋ぎ直しました」は出さない）",
             state: "crashed", want: true, event: "restored", launchAtLogin: true,
             expected: ["落ちました。自動で繋ぎ直します"]),
    NoteCase(title: "未信頼のフォルダは自動では踏まない",
             state: "untrusted", want: true, event: nil, launchAtLogin: true,
             expected: ["初回の確認が済むまで、自動では繋ぎ直しません"]),
    NoteCase(title: "ログイン時に起動しないなら、再起動後は戻らないと言う",
             state: "online", want: true, event: nil, launchAtLogin: false, expected: [loginHint]),
    NoteCase(title: "落ちた記録とログインの注意は両方出す",
             state: "online", want: true, event: "restored", launchAtLogin: false,
             expected: ["落ちたので 9/23 14:05 に繋ぎ直しました", loginHint]),
]

/// 「前回の更新」のあらまし（Issue #183）。記録の形ごとに、行に出る1行を見る。
private struct DigestCase {
    let title: String
    let report: String
    let headline: String
    let hasDetail: Bool
}

/// 実物をそのまま持ってくる。作った形だけで確かめると、記録を書く側が変わった
/// ときに検査だけ通り続ける。1件目は 2026-09-15 に実際に書かれたもの。
private let digestCases: [DigestCase] = [
    DigestCase(
        title: "版が4つ動いた日（実物）",
        report: """
        9/15 22:06
        MulmoTerminal: 4.21.0 → 4.25.0
        MulmoClaude: 1.16.0 → 1.17.0
        MulmoBridge CLI: 1.0.2 → 1.0.3
        Slack Bridge: 1.1.0 → 1.1.1
        更新の内容（MulmoTerminal）
        ・Start without Claude Code, by declaring the agent you do have
        ガイド: https://receptron.github.io/mulmoterminal/guide/ja/v4.25.0.html
        更新の内容（MulmoClaude）
        ・Choose the model — per setting, per role, or per chat
        詳しく: https://github.com/receptron/mulmoclaude/releases/tag/v1.17.0
        """,
        headline: "9/15 22:06 ・ 4件を更新",
        hasDetail: true
    ),
    DigestCase(
        title: "一部だけ動いた日",
        report: """
        9/3 10:00
        MulmoTerminal: 4.21.0 → 4.25.0
        更新されなかったもの:
        MulmoClaude: 1.16.0 のまま — npm が繋がりませんでした
        MulmoBridge CLI: 1.0.2 のまま
        """,
        headline: "9/3 10:00 ・ 1件を更新 / 2件そのまま",
        hasDetail: true
    ),
    DigestCase(
        title: "1つも動かなかった日（ログの行は数に入れない）",
        report: """
        9/3 10:00
        更新されなかったもの:
        MulmoClaude: 1.16.0 のまま
        ログ: /Users/me/Library/Logs/Mulmo Control
        """,
        headline: "9/3 10:00 ・ 1件そのまま",
        hasDetail: true
    ),
    DigestCase(
        title: "更新直後の知らせ（実物・日付なし・1件だけ動いた）",
        report: """
        MulmoClaude: 1.18.0 → 1.19.0
        更新の内容（MulmoClaude）
        ・a custom view's button can start the work
        ・A custom view's button runs the chat
        ・The firebase pin from the sign-in regression is lifted
        ・Dependency refresh and steadier end-to-end tests
        詳しく: https://github.com/receptron/mulmoclaude/releases/tag/v1.19.0
        """,
        headline: "MulmoClaude: 1.18.0 → 1.19.0",
        hasDetail: true
    ),
    DigestCase(
        title: "1件だけ動いた日（前回の更新・日付つき）",
        report: """
        9/20 1:57
        MulmoClaude: 1.18.0 → 1.19.0
        更新の内容（MulmoClaude）
        ・Dependency refresh
        """,
        headline: "9/20 1:57 ・ MulmoClaude: 1.18.0 → 1.19.0",
        hasDetail: true
    ),
    DigestCase(
        title: "まだ一度も更新していない",
        report: "まだありません",
        headline: "まだありません",
        hasDetail: false
    ),
    DigestCase(
        title: "数えられない記録は、書いてあるものを出す",
        report: """
        9/3 10:00
        変更内容は確認できませんでした
        """,
        headline: "9/3 10:00 ・ 変更内容は確認できませんでした",
        hasDetail: true
    ),
    DigestCase(
        title: "日付が無くても落とさない",
        report: "変更内容は確認できませんでした",
        headline: "変更内容は確認できませんでした",
        hasDetail: false
    ),
]

@main
struct StatusDisplayTest {
    static func main() {
        var failures = 0

        // ① 12通りが1つずつ、過不足なく並んでいるか
        var seen = Set<String>()
        for item in cases { seen.insert("\(item.state)/\(stash(item.hasStash))") }
        if seen.count != cases.count {
            FileHandle.standardError.write(Data("表に同じ組み合わせが2度出ています\n".utf8))
            failures += 1
        }
        for state in states {
            for value in stashes {
                if !seen.contains("\(state)/\(stash(value))") {
                    FileHandle.standardError.write(Data(
                        "  state=\(state) hasStash=\(stash(value)) が表にありません\n".utf8))
                    failures += 1
                }
            }
        }

        // ② それぞれ、出る言葉が期待どおりか
        for item in cases {
            let status = RemoteHostStatus(
                checkedAt: "2026-08-28T00:00:00Z",
                state: item.state,
                hasSession: false,
                detail: "",
                hasStash: item.hasStash
            )
            let actual = remoteHostButtonTitle(status)
            if actual != item.expected {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  state=\(item.state) hasStash=\(stash(item.hasStash)): 期待 \(show(item.expected)) / 実際 \(show(actual))\n".utf8
                ))
            }
        }
        // ③ エージェントのスマホ連携（Issue #160）
        let agents = agentCases()
        if agents.count != 18 {
            FileHandle.standardError.write(Data("エージェント連携の組み合わせが18通りありません\n".utf8))
            failures += 1
        }
        for item in agents {
            let status = AgentRemote(
                state: item.state, detail: "",
                url: item.hasURL ? "https://claude.ai/code/session_01ABC" : "",
                pairCode: nil
            )
            let button = agentRemoteButtonTitle(status)
            if button != item.expectedButton {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  state=\(item.state) url=\(item.hasURL): ボタンの期待 \(show(item.expectedButton)) / 実際 \(show(button))\n".utf8))
            }
            let codexButton = codexButtonTitle(status)
            if codexButton != item.expectedCodexButton {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  state=\(item.state): Codex のボタンの期待 \(show(item.expectedCodexButton)) / 実際 \(show(codexButton))\n".utf8))
            }
            if agentRemoteOK(status) != item.expectedOK {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  state=\(item.state): 印の期待 \(item.expectedOK) / 実際 \(agentRemoteOK(status))\n".utf8))
            }
            if agentRemoteCanStop(status) != item.expectedCanStop {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  state=\(item.state): 止める口の期待 \(item.expectedCanStop) / 実際 \(agentRemoteCanStop(status))\n".utf8))
            }
        }

        // ④ 自動の繋ぎ直しの知らせ（Issue #212）
        for item in noteCases {
            let status = AgentRemote(
                state: item.state, detail: "", url: nil, pairCode: nil,
                want: item.want, event: item.event,
                eventAt: item.event == nil ? nil : "9/23 14:05"
            )
            let notes = claudeRemoteNotes(status, launchAtLogin: item.launchAtLogin)
            if notes != item.expected {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  \(item.title): 知らせの期待 \(item.expected) / 実際 \(notes)\n".utf8))
            }
        }

        // ⑤ 「前回の更新」のあらまし（Issue #183）
        for item in digestCases {
            let digest = lastUpdateDigest(item.report)
            if digest.headline != item.headline {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  \(item.title): あらましの期待 \(item.headline) / 実際 \(digest.headline)\n".utf8))
            }
            if digest.hasDetail != item.hasDetail {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  \(item.title): 開く口の期待 \(item.hasDetail) / 実際 \(digest.hasDetail)\n".utf8))
            }
        }

        if failures > 0 {
            FileHandle.standardError.write(Data("\(failures) 件、状態と表示が食い違っています\n".utf8))
            exit(1)
        }
        print("\(cases.count) 通り + エージェント連携 \(agents.count) 通り + 繋ぎ直しの知らせ \(noteCases.count) 通り + 更新のあらまし \(digestCases.count) 通りすべて一致")
    }
}
