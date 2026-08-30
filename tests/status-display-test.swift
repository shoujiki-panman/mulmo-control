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
    let expectedOK: Bool
    let expectedCanStop: Bool
}

/// 状態 × 入口の有無。表を手で並べず、軸から組み立てる。1行消すと落ちる。
private func agentCases() -> [AgentCase] {
    var built: [AgentCase] = []
    for state in ["online", "taken", "offline", "untrusted", "error", "no-cli", "no-dir"] {
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
            built.append(AgentCase(
                state: state, hasURL: hasURL, expectedButton: button,
                expectedOK: state == "online" || state == "taken",
                expectedCanStop: state == "online" || state == "error"
            ))
        }
    }
    return built
}

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
        if agents.count != 14 {
            FileHandle.standardError.write(Data("エージェント連携の組み合わせが14通りありません\n".utf8))
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

        if failures > 0 {
            FileHandle.standardError.write(Data("\(failures) 件、状態と表示が食い違っています\n".utf8))
            exit(1)
        }
        print("\(cases.count) 通り + エージェント連携 \(agents.count) 通りすべて一致")
    }
}
