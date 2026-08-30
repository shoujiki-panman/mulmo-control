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
private struct ProjectCase {
    let exists: Bool
    let running: Bool
    let trusted: Bool
    let expectedDetail: String
    let expectedButton: String?
}

private func projectCases() -> [ProjectCase] {
    var built: [ProjectCase] = []
    for exists in [true, false] {
        for running in [true, false] {
            for trusted in [true, false] {
                let detail: String
                if !exists {
                    detail = "フォルダが見つかりません"
                } else if !running {
                    detail = trusted ? "停止中" : "停止中・初回は確認が要ります"
                } else {
                    detail = "s1"
                }
                let button: String? = exists ? (running ? "止める" : "繋ぐ") : nil
                built.append(ProjectCase(exists: exists, running: running, trusted: trusted,
                                         expectedDetail: detail, expectedButton: button))
            }
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
        // ③ プロジェクトの行（Issue #152）
        let projects = projectCases()
        if projects.count != 8 {
            FileHandle.standardError.write(Data("プロジェクトの組み合わせが8通りありません\n".utf8))
            failures += 1
        }
        for item in projects {
            let project = ProjectSession(
                name: "p", path: "~/p", exists: item.exists, trusted: item.trusted,
                autoStart: false, sessionName: item.running ? "s1" : "",
                status: item.running ? "running" : "stopped"
            )
            let detail = projectSessionDetail(project)
            if detail != item.expectedDetail {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  実在=\(item.exists) 動作=\(item.running) 信頼=\(item.trusted): 期待 \(item.expectedDetail) / 実際 \(detail)\n".utf8))
            }
            let button = projectButtonTitle(project)
            if button != item.expectedButton {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  実在=\(item.exists) 動作=\(item.running): ボタンの期待 \(show(item.expectedButton)) / 実際 \(show(button))\n".utf8))
            }
            let expectOK = item.exists && item.running
            if projectSessionOK(project) != expectOK {
                failures += 1
                FileHandle.standardError.write(Data(
                    "  実在=\(item.exists) 動作=\(item.running): 印の期待 \(expectOK) / 実際 \(projectSessionOK(project))\n".utf8))
            }
        }

        if failures > 0 {
            FileHandle.standardError.write(Data("\(failures) 件、状態と表示が食い違っています\n".utf8))
            exit(1)
        }
        print("\(cases.count) 通り + プロジェクト \(projects.count) 通りすべて一致")
    }
}
