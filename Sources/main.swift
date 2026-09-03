import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

/// 追加ツールの入れ先。mulmo-check-updates が版を読むのも同じ場所でなければ
/// ならない（Issue #129）。以前はここを2箇所に書き、読む側は知らなかったので、
/// npm が新しい版を入れても画面は古いままで「更新できませんでした」と言い続けた。
private let familyPrefix = "\(homeDir)/.local/share/mulmo-family"
private let localBin = "\(homeDir)/.local/bin"

// MulmoTerminal のポート。3箇所に数字が散っていて、変えるときに拾い漏れる形
// だった（Issue #7）。スクリプト側の既定は mulmoterminal-agent-env が持つので、
// 既定値を動かすときは両方を合わせること。
private let mtPort = 34567
private let mtURL = "http://localhost:\(mtPort)"
// 補助スクリプトの置き場所。build-app.sh が Contents/Resources/scripts に同梱するので、
// 通常はそこを見る。zip を Applications にドラッグしただけでも全ボタンが動くのは
// これが理由（Issue #11）。
//
// 旧 install.sh がコピーしていた ~/Documents/Codex/SwiftBarTools には、同梱版が
// 見つからないときだけ落ちる。バンドルの外で生のバイナリを起動する開発時と、
// 同梱前のバンドルが残っている場合のための保険で、通常の経路では使われない。
private let toolsDir: String = {
    let legacy = "\(homeDir)/Documents/Codex/SwiftBarTools"
    guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("scripts").path else { return legacy }
    return FileManager.default.fileExists(atPath: bundled) ? bundled : legacy
}()

// zsh -lc に渡すコマンド文字列へスクリプトのパスを埋めるときは、必ずこの2つを通す。
//
// 同梱先が `/Applications/Mulmo Control.app/...` で空白を含むため、裸で埋め込むと
// そこで切れて `/Applications/Mulmo` を実行しようとする（Issue #32）。旧 SwiftBarTools
// には空白がなく、#11 で移すまで露見しなかった。localBin 側も、ユーザー名に空白が
// あれば同じ壊れ方をする。
//
// FileManager に渡す「本物のパス」には使わないこと（引用符が名前の一部になる）。
/// いま動いているアプリの版（Issue #10）。app-info.env のような記録ではなく、
/// 実行中のバンドル自身から読む。リリースタグ v1.0.12 と同じ文字列になる。
let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

private func tool(_ name: String) -> String { "\"\(toolsDir)/\(name)\"" }
private func bin(_ name: String) -> String { "\"\(localBin)/\(name)\"" }
private func shellQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
/// ログと状態ファイルの置き場所（Issue #4）。
///
/// 以前は ~/Documents/Codex/SwiftBarLogs だった。SwiftBar は Mulmo Control とは
/// 別のツールで、作者の環境から持ち越した名前。他人の Mac に、入れた覚えのない
/// 名前のフォルダが Documents にできていた。Documents を iCloud で同期している
/// 人には同期対象にもなる。macOS が用意している場所へ移した。
private let logDir = "\(homeDir)/Library/Logs/Mulmo Control"
/// ボタンを押したときの出力先。以前は `/tmp/mulmo-control-action.log` にあり、
/// ログは1箇所に揃える約束（#4）から外れていた。`/tmp` は誰でも書けるので、
/// 固定名だと先に同名のリンクを置かれる余地もある（Issue #104）。
private let actionLogPath = "\(logDir)/mulmo-control-action.log"

/// 失敗したときに画面へ添える一行。作業ログの末尾から、中身のある行を1つ拾う。
///
/// 「失敗しました。ログを確認してください」だけでは、ターミナルを開かせない
/// というこのアプリの役目を果たしていない（Issue #104）。yarn が見つからない
/// ときの `yarn was not found` は、この一行で画面に出る。
func lastLineOfActionLog(limit: Int = 120) -> String? {
    guard let text = try? String(contentsOfFile: actionLogPath, encoding: .utf8) else { return nil }
    let line = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .last { !$0.isEmpty }
    guard let line, !line.isEmpty else { return nil }
    return line.count <= limit ? line : String(line.prefix(limit)) + "…"
}
private let legacyLogDir = "\(homeDir)/Documents/Codex/SwiftBarLogs"

/// 古い置き場所から一度だけ引き継ぐ。
///
/// やらないと、これまでの更新履歴が消えたように見える。上書きはしない
/// （新しい場所に既にあるほうが新しい）。移し終えても古いフォルダは消さない。
/// 中に SwiftBar 本体のログなど、こちらの与り知らぬものが混ざっている
/// 可能性があるため。
private func migrateLegacyLogsIfNeeded() {
    // 一度やったら、二度と ~/Documents を見ない（Issue #134）。
    //
    // 見に行くだけで macOS は「"書類" フォルダ内のファイルへのアクセス権を
    // 求められています」を出す。引き継ぎは一度で済むのに、毎起動で聞きに
    // 行っていた。Documents を iCloud で同期している人には、こちらの与り
    // 知らぬフォルダを毎回開くことにもなる。#4 で移した理由そのもの。
    //
    // 印は「やる前」に立てる。拒否されたときに毎回聞き直すのを避けるため。
    // 引き継ぐのは SwiftBar 時代のログで、新しい置き場所には既に全部ある。
    let mark = "mulmo-control.legacy-logs-migrated"
    guard !UserDefaults.standard.bool(forKey: mark) else { return }
    UserDefaults.standard.set(true, forKey: mark)

    let fm = FileManager.default
    guard fm.fileExists(atPath: legacyLogDir) else { return }
    try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    guard let names = try? fm.contentsOfDirectory(atPath: legacyLogDir) else { return }
    for name in names where name.hasPrefix("mulmo") || name.hasPrefix("claude-") || name.hasPrefix("remote-host") {
        let to = "\(logDir)/\(name)"
        guard !fm.fileExists(atPath: to) else { continue }
        try? fm.copyItem(atPath: "\(legacyLogDir)/\(name)", toPath: to)
    }
}

private let updatePath = "\(logDir)/mulmoterminal-update.json"
private let mulmoUpdatesPath = "\(logDir)/mulmo-updates.json"
private let selfUpdatePath = "\(logDir)/mulmo-control-self-update.json"
private let claudeLoginPath = "\(logDir)/claude-login.json"
private let remoteHostPath = "\(logDir)/remote-host.json"
// スマホ連携は2つある。MulmoTerminal(34567) はターミナルを、MulmoClaude(3001) は
// チャットをスマホから操作するためのもので、同じアカウントを使うが接続は別々
// （Issue #78）。以前は前者しか見ていないのに主語なしで「スマホ連携」と出して
// いたので、MulmoClaude 側が切れていても「使えます」と表示していた。
private let mcRemoteHostPath = "\(logDir)/remote-host-mulmoclaude.json"
private let claudeRemotePath = "\(logDir)/claude-remote.json"
private let codexRemotePath = "\(logDir)/codex-remote.json"
private let lastUpdateReportPath = "\(logDir)/mulmo-control-last-update.txt"
/// 更新スクリプトが「なぜ版が変わらなかったか」を書き置く場所。
/// 以前は「ログを見てください」で終わっていて、利用者には何も分からなかった（Issue #46）。
private let updateReasonsPath = "\(logDir)/mulmo-update-reasons.txt"
private let lastUpdateSummaryPath = "\(logDir)/mulmo-control-last-update-summary.txt"
/// 直近のリリースの内容（Issue #176）。`scripts/mulmo-release-notes` が控える。
private let releaseNotesPath = "\(logDir)/mulmo-control-release-notes.md"
let mulmoControlReleases = "https://github.com/shoujiki-panman/mulmo-control/releases"

/// 更新を勧めておいて中身を見せないのは筋が悪い（Issue #176）。ここが無かった
/// ので、v1.0.61 で開くアドレスが変わったことの理由と戻し方に、アプリからは
/// 辿り着けなかった。
struct ReleaseNotes {
    let tag: String
    let date: String
    let body: String
}

/// 1行目がタグ、2行目が公開日、残りが本文。控えが無ければ nil。
/// **取れていないことは失敗ではない。** 呼ぶ側は nil でも GitHub へ飛ぶ口を出す。
func readReleaseNotes() -> ReleaseNotes? {
    guard let text = try? String(contentsOfFile: releaseNotesPath, encoding: .utf8) else { return nil }
    let lines = text.components(separatedBy: "\n")
    guard lines.count > 2 else { return nil }
    let body = lines.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lines[0].isEmpty, !body.isEmpty else { return nil }
    return ReleaseNotes(tag: lines[0], date: lines[1], body: body)
}
/// MulmoClaude をどちらのモードで起こすか（Issue #168）。
///
/// `app` は production serve。ビルド済みの画面を配るだけなので Vite は立たず、
/// ファイルが変わっても画面は作り直されない。`dev` は `yarn dev` で、保存の
/// たびに開いている全タブがリロードされる。MulmoClaude は使うだけで自分の
/// フォルダにファイルを書くアプリなので、開発モードで日常使いすると入力中の
/// 文字と貼った添付が飛ぶ（本家 receptron/mulmoclaude#2919 は「dev server の
/// 定義どおりの動作」として NOT_PLANNED）。どちらで起こすかを選べるように
/// するのがここ。
///
/// 既定は `app`（Issue #174）。#168 では `dev` にした — 「いま使っている人の
/// 挙動を変えない」ためだったが、**開発者モードを選んだ人は一人もいなかった。**
/// 他に道が無かっただけで、しかも気づく手がかりが1つも無い。守っていたのは
/// 選択ではなく事故だった。
///
/// 置き場所は app-info.env ではない。install.sh はあのファイルを更新のたびに
/// 丸ごと書き直すので（install.sh:132）、置くと更新のたびにモードが戻る。
/// 初回通知の印を UserDefaults に置いたのと同じ理由。
///
/// ポートと URL の対応表を持つのはここと `scripts/mulmoclaude-ports` /
/// `scripts/mulmoclaude-url` の2箇所。Swift 側が同じファイルを直接読むのは、
/// メニューを開くたびの refresh でシェルを起こしたくないため（Issue #38 で
/// 一度払った代償）。食い違わないことは check.sh が突き合わせている。
enum MulmoClaudeMode: String {
    case app
    case dev

    static let filePath = "\(homeDir)/Library/Application Support/Mulmo Control/mulmoclaude-mode"

    static func current() -> MulmoClaudeMode {
        guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else { return .app }
        let word = text.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return MulmoClaudeMode(rawValue: word) ?? .app
    }

    /// 自分で選んだことがあるか。既定が変わったことを知らせる相手を決めるのに使う。
    static var chosen: Bool { FileManager.default.fileExists(atPath: filePath) }

    /// 通常モードでは Vite が立たないので 5173 は開かない。
    var ports: [Int] { self == .app ? [3001] : [5173, 3001] }

    /// 身元を確かめに行く先（Issue #93）。画面を配っているほうを見る。
    var probePort: Int { self == .app ? 3001 : 5173 }

    var url: String { "http://localhost:\(probePort)" }

    var label: String { self == .app ? "通常モード" : "開発モード" }

    var detail: String {
        self == .app
            ? "画面は作り済みのものを配ります。作業中に勝手にリロードされません"
            : "保存のたびに画面が作り直されます。MulmoClaude 自体を開発する人向け"
    }

    /// パネルの1行目に添える一言（Issue #170）。押さずに、いまどちらで
    /// 動いているかが分かる必要がある — 画面が勝手にリロードされるかどうかが
    /// ここで決まっているため。
    var note: String {
        self == .app ? "作業中にリロードされません" : "保存すると画面が作り直されます"
    }
}

/// 書くのは1語だけ。読む側（`scripts/mulmoclaude-mode`）が知らない語を既定へ
/// 倒すので、壊れた値が起動コマンドまで届くことはない。
func writeMulmoClaudeMode(_ mode: MulmoClaudeMode) {
    let path = MulmoClaudeMode.filePath
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? "\(mode.rawValue)\n".write(toFile: path, atomically: true, encoding: .utf8)
}

// install.sh が書き出す app-info.env から MulmoClaude の場所を読む
private func configuredMulmoClaudeDir() -> String {
    let fallback = "\(homeDir)/mulmoclaude"
    let configPath = "\(homeDir)/Library/Application Support/Mulmo Control/app-info.env"
    guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else { return fallback }
    let key = "MULMO_CONTROL_MULMOCLAUDE_DIR="
    for line in text.split(separator: "\n") {
        guard line.hasPrefix(key) else { continue }
        let value = parseShellEnvValue(line.dropFirst(key.count))
        if !value.isEmpty { return value }
    }
    return fallback
}

private func parseShellEnvValue(_ raw: Substring) -> String {
    var value = String(raw).trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
        value.removeFirst()
        value.removeLast()
        return value.replacingOccurrences(of: "'\\''", with: "'")
    }
    if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
        value.removeFirst()
        value.removeLast()
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    return value
}

private let mulmoClaudeDir = configuredMulmoClaudeDir()
private let mulmoClaudeRepo = "https://github.com/receptron/mulmoclaude"

struct MulmoUpdateItem: Identifiable, Decodable {
    let id: String
    let name: String
    let current: String
    let latest: String
    let status: String
}

extension MulmoUpdateItem {
    var displayName: String {
        switch id {
        case "mulmoterminal":
            return "MulmoTerminal"
        case "mulmoclaude":
            return "MulmoClaude"
        case "mulmocast":
            return "MulmoCast"
        case "mulmocast-vision":
            return "MulmoCast Vision"
        case "mulmobridge-client":
            return "MulmoBridge Client"
        case "mulmobridge-cli":
            return "MulmoBridge CLI"
        case "mulmobridge-slack":
            return "Slack Bridge"
        case "create-plugin":
            return "Plugin Creator"
        default:
            return name
        }
    }
}

struct MulmoUpdates: Decodable {
    let checkedAt: String
    let summary: String
    let items: [MulmoUpdateItem]
}

/// claude CLI のログイン状態。MulmoClaude は内部で claude を呼ぶので、
/// ここが切れるとチャットだけが死ぬ。サーバーは動いたままなので気づきにくい。
struct ClaudeLoginStatus: Decodable {
    let checkedAt: String
    let state: String   // ok / expired / unknown
    let detail: String

    var isExpired: Bool { state == "expired" }
}

struct SelfUpdateStatus: Decodable {
    // 全て省略可にしてある。項目が1つ足りないだけで丸ごと復号に失敗し、
    // 画面が「未確認」に落ちるのを避けるため（Issue #31 で installedCommit を
    // installedVersion に置き換えたとき、古い JSON が残っていても壊れない）。
    var checkedAt: String = ""
    var status: String = "unknown"
    /// 実際に /Applications に入っているアプリの版。
    var installedVersion: String = ""
    /// 最新のリリースタグ。
    var latestVersion: String = ""
    var detail: String = ""
}

struct FamilyPackage: Identifiable {
    let id: String
    let title: String
    let packageName: String
    let commandName: String
    let note: String
    let capability: String
    let useWhere: String
    var isInstallable = true
}

struct NoticeMessage: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private let familyPackages = [
    FamilyPackage(
        id: "mulmocast",
        title: "MulmoCast",
        packageName: "mulmocast",
        commandName: "mulmocast",
        note: "台本・動画生成",
        capability: "MulmoScriptから音声・画像・動画・PDF・HTMLなどの成果物を生成します。",
        useWhere: "MulmoTerminalの作業セル、またはターミナルで mulmo コマンドとして使います。"
    ),
    FamilyPackage(
        id: "mulmocast-vision",
        title: "MulmoCast Vision",
        packageName: "mulmocast-vision",
        commandName: "mulmocast-vision",
        note: "画像/視覚処理",
        capability: "画像や視覚情報を扱うMulmoCast系の補助ツールです。",
        useWhere: "画像を含むMulmo制作や、MulmoTerminal内の作業から呼び出します。"
    ),
    FamilyPackage(
        id: "mulmobridge-cli",
        title: "MulmoBridge CLI",
        packageName: "@mulmobridge/cli",
        commandName: "mulmobridge-cli",
        note: "Bridge操作",
        capability: "MulmoBridgeの接続・設定・操作をCLIから扱うためのツールです。",
        useWhere: "Bridge連携をセットアップするときに、MulmoTerminalや通常のターミナルから使います。"
    ),
    FamilyPackage(
        id: "mulmobridge-slack",
        title: "Slack Bridge",
        packageName: "@mulmobridge/slack",
        commandName: "mulmobridge-slack",
        note: "Slack連携",
        capability: "SlackとMulmoBridge/MulmoClaudeをつなぐための連携ツールです。",
        useWhere: "Slack Bot/App Tokenを設定した上で、Slack連携を動かす環境で使います。"
    ),
    FamilyPackage(
        id: "create-plugin",
        title: "Plugin Creator",
        packageName: "create-mulmoclaude-plugin",
        commandName: "create-mulmoclaude-plugin",
        note: "プラグイン作成",
        capability: "MulmoClaude向けプラグインのひな形を作るためのツールです。",
        useWhere: "新しいプラグインを作り始めるときに、作業フォルダのターミナルから使います。",
        isInstallable: false
    )
]

enum AppFont {
    static let appTitle = Font.system(size: 19, weight: .semibold, design: .default)
    static let tab = Font.system(size: 13, weight: .semibold, design: .default)
    static let section = Font.system(size: 15, weight: .semibold, design: .default)
    static let cardTitle = Font.system(size: 17, weight: .semibold, design: .default)
    static let rowTitle = Font.system(size: 12.5, weight: .semibold, design: .default)
    static let body = Font.system(size: 12, weight: .medium, design: .default)
    static let small = Font.system(size: 11, weight: .medium, design: .default)
    static let action = Font.system(size: 12, weight: .semibold, design: .default)
}

@MainActor
final class ControlModel: ObservableObject {
    @Published var mtRunning = false
    @Published var mcRunning = false
    /// 二重に走らせない印（Issue #116）。
    private var lightChecksRunning = false
    @Published var nodePath: String?
    @Published var npmPath: String?
    @Published var mtInstalled = false
    @Published var mcInstalled = false
    @Published var updateText = "更新: 未確認"
    @Published var updateSummary = "更新: 未確認"
    @Published var updateItems: [MulmoUpdateItem] = []
    @Published var selfUpdate = readSelfUpdateStatus()
    @Published var claudeLogin = readClaudeLoginStatus()
    @Published var remoteHost = readRemoteHostStatus()
    @Published var mcRemoteHost = readRemoteHostStatus(mcRemoteHostPath)
    @Published var claudeRemote = readAgentRemote(claudeRemotePath)
    @Published var codexRemote = readAgentRemote(codexRemotePath)
    @Published var familyInstalled: [String: Bool] = [:]
    @Published var actionText: String?
    @Published var notice: NoticeMessage?
    @Published var lastUpdateReport = readLastUpdateReport()
    /// 直近のリリースの内容（Issue #176）。ファイルを読むだけ。
    @Published var releaseNotes = readReleaseNotes()
    /// MulmoClaude をどちらのモードで起こすか（Issue #168）。
    @Published var mcMode = MulmoClaudeMode.current()

    private var timer: Timer?
    private var notifiedUpdateKey = UserDefaults.standard.string(forKey: "mulmo-control.notified-update-key")
    private var notifiedSelfUpdateKey = UserDefaults.standard.string(forKey: "mulmo-control.notified-self-update-key")
    private var notifiedClaudeLoginAt = UserDefaults.standard.string(forKey: "mulmo-control.notified-claude-login-at")
    private var pendingUpdateReport: [MulmoUpdateItem]?
    private var pendingUpdateReportTitle: String?
    /// 更新を走らせる直前の実測バージョン（id → version）。
    private var beforeVersions: [String: String] = [:]
    private var lastAutomaticUpdateCheck = Date.distantPast
    private var automaticUpdateCheckRunning = false

    /// 画面（ポップオーバー）が開いているか。開いている間だけ細かく巡回する。
    private var panelIsOpen = false

    /// `commandPath` の結果。1回が `zsh -lc`（ログインシェル）なので、5秒ごとに
    /// 呼ぶには高すぎた（Issue #38）。node や npm の場所は普段変わらないため
    /// 憶えておき、何かを入れたあと（`run` の完了時）にだけ捨てる。
    /// 値が nil の「見つからなかった」も憶える（`[String: String?]` の二重 Optional）。
    private var commandPathCache: [String: String?] = [:]

    func cachedCommandPath(_ name: String) -> String? {
        if let hit = commandPathCache[name] { return hit }
        let resolved = commandPath(name)
        commandPathCache[name] = resolved
        return resolved
    }

    private func invalidateCommandPathCache() { commandPathCache.removeAll() }

    /// 何かを実行したあとの更新。ツールが増えたり消えたりしている可能性があるので、
    /// 憶えているコマンドの場所は捨ててから読み直す。
    private func refreshAfterAction() {
        invalidateCommandPathCache()
        refresh()
    }

    /// 開いている間の巡回間隔。画面の表示を追従させるための値。
    private static let activeInterval: TimeInterval = 5
    /// 閉じている間の巡回間隔。メニューバーのアイコン（起動状態・更新の有無）が
    /// 保てればよいので、こちらは粗くてよい（Issue #38）。
    private static let idleInterval: TimeInterval = 60

    init() {
        migrateLegacyLogsIfNeeded()
        requestNotificationPermission()
        refresh()
        checkUpdatesSilentlyIfNeeded(force: true)
        scheduleTimer()
    }

    /// ポップオーバーの開閉に合わせて巡回の粗さを切り替える。
    ///
    /// 閉じている間も 5 秒ごとに外部プロセスを8つ起動していて、macOS に
    /// 「エネルギーを著しく消費中」と言われていた（Issue #38）。見ていない間は
    /// 60 秒に落とし、UI にしか要らない調査（コマンドの場所）も省く。
    func setPanelOpen(_ open: Bool) {
        guard panelIsOpen != open else { return }
        panelIsOpen = open
        scheduleTimer()
        if open {
            refresh()
            refreshLightChecks()
        }
    }

    /// パネルを開いたときに、書き置きを取り直す（Issue #116）。
    ///
    /// 「動作中」はその場でポートを見るが、スマホ連携と Claude のログインは
    /// スクリプトが書いたファイルを読んでいるだけだった。そのファイルを書くのは
    /// `確認` ボタンと6時間ごとの自動確認だけなので、繋ぎ直しても画面は切れた
    /// ままの表示が残っていた。
    ///
    /// ここで走らせるのは軽い3つだけ（実測でスマホ連携 101ms・ログイン 203ms・
    /// プロジェクト 51ms）。npm を叩く更新確認は 2750ms かかるので、6時間の
    /// 間隔のまま触らない。
    private func refreshLightChecks() {
        guard !lightChecksRunning else { return }
        lightChecksRunning = true
        let command = """
        \(tool("mulmo-check-remote-host"))
        \(tool("mulmo-check-claude-login"))
        \(tool("mulmo-claude-remote")) status
        \(tool("mulmo-codex-remote")) status
        """
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            try? process.run()
            process.waitUntilExit()
            await MainActor.run {
                guard let self else { return }
                self.lightChecksRunning = false
                self.remoteHost = readRemoteHostStatus()
                self.mcRemoteHost = readRemoteHostStatus(mcRemoteHostPath)
                self.claudeLogin = readClaudeLoginStatus()
                self.claudeRemote = readAgentRemote(claudeRemotePath)
                self.codexRemote = readAgentRemote(codexRemotePath)
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = panelIsOpen ? Self.activeInterval : Self.idleInterval
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // 閉じている間は時刻がずれてもよいので、まとめて起こしてもらう。
        // 単独で CPU を起こす回数が減る。
        t.tolerance = interval / 2
        timer = t
    }

    var menuIconName: String {
        // ログイン切れは更新より先に出す。更新は後回しにできるが、
        // ログインが切れている間は MulmoClaude のチャットが使えない。
        if claudeLogin.isExpired { return "exclamationmark.triangle.fill" }
        return hasAnyUpdates ? "arrow.down.circle.fill" : "terminal.fill"
    }

    var hasAvailableUpdates: Bool {
        updateItems.contains { $0.status == "update" }
    }

    var hasSelfUpdate: Bool {
        selfUpdate.status == "update"
    }

    var hasAnyUpdates: Bool {
        hasAvailableUpdates || hasSelfUpdate
    }

    /// 5173 の身元は取りに行かないと分からないので、控えに置いて refresh() は
    /// それを読む（Issue #93）。ここで待つとメニューを開くたびに固まる。
    private var mcIdentity = false
    private var mcIdentityChecking = false

    /// ポートが閉じていれば即座に「動いていない」。開いていたら中身を確かめる。
    /// 確かめ終わるまでは前回分かった値を返す。起動直後に一瞬「停止中」と出るが、
    /// 他人のものを「動作中」と言うよりはよい。
    private func mulmoClaudeIsRunning() -> Bool {
        guard mcMode.ports.contains(where: portIsOpen) else {
            mcIdentity = false
            return false
        }
        confirmMulmoClaudeIdentity()
        return mcIdentity
    }

    private func confirmMulmoClaudeIdentity() {
        guard !mcIdentityChecking else { return }
        mcIdentityChecking = true
        let port = mcMode.probePort
        Task.detached { [weak self] in
            let confirmed = servesMulmoClaude(port: port)
            await MainActor.run {
                guard let self else { return }
                self.mcIdentityChecking = false
                self.mcIdentity = confirmed
                self.mcRunning = confirmed
            }
        }
    }

    func refresh() {
        // ポート確認とファイル読みだけ。メニューバーのアイコンはこれで足りるので、
        // 閉じている間はここまでで済ませる（Issue #38）。
        mtRunning = portIsOpen(mtPort)
        // 起動より先に読む。ポートも URL もここから決まるので、古いモードの
        // まま判定すると「起動したのに停止中と出る」になる。
        mcMode = MulmoClaudeMode.current()
        releaseNotes = readReleaseNotes()
        mcRunning = mulmoClaudeIsRunning()
        mtInstalled = FileManager.default.isExecutableFile(atPath: "\(localBin)/mulmoterminal")
        // 「入っている」の意味は、スクリプト側と揃える（Issue #107）。
        // 以前はフォルダの有無だけを見ていたので、空のフォルダを指していると
        // 画面は緑で「インストール済み」、更新は毎回 `repo was not found` で
        // 失敗、という食い違いが起きた。しかも `入手` ボタンが消えるので、
        // 入れ直す導線まで塞がっていた。
        mcInstalled = FileManager.default.fileExists(atPath: "\(mulmoClaudeDir)/.git")
        updateText = readUpdateText()
        let updates = readMulmoUpdates()
        updateSummary = updates.summary
        updateItems = updates.items
        selfUpdate = readSelfUpdateStatus()
        claudeLogin = readClaudeLoginStatus()
        remoteHost = readRemoteHostStatus()
        mcRemoteHost = readRemoteHostStatus(mcRemoteHostPath)
        claudeRemote = readAgentRemote(claudeRemotePath)
        codexRemote = readAgentRemote(codexRemotePath)
        notifyIfNeeded(for: updates.items)
        notifySelfUpdateIfNeeded(selfUpdate)
        notifyClaudeLoginIfNeeded(claudeLogin)

        // ここから下は画面にしか出ない情報で、コマンドの場所を調べる分だけ高くつく。
        // 閉じている間は省く。
        if panelIsOpen {
            refreshToolPaths()
        }
        checkUpdatesSilentlyIfNeeded()
    }

    /// node / npm / 追加ツールの在り処。結果は憶えておくので、実際にコマンドを
    /// 探しに行くのは初回と、何かを入れたあとだけ。
    private func refreshToolPaths() {
        nodePath = cachedCommandPath("node")
        npmPath = cachedCommandPath("npm")
        familyInstalled = Dictionary(uniqueKeysWithValues: familyPackages.map { package in
            (package.id, familyCommandPath(package) != nil)
        })
    }

    func openMT() {
        guard mtInstalled else {
            showMessage(title: "MulmoTerminalが未インストールです", text: "先にインストールしてください。")
            return
        }
        if mtRunning {
            openURL(mtURL)
        } else {
            runThenOpen(tool("mulmoterminal-start"), url: mtURL)
        }
    }

    func openMC() {
        guard mcInstalled else {
            showMessage(title: "MulmoClaudeが未インストールです", text: "先にインストールしてください。")
            return
        }
        if mcRunning {
            openURL(mcMode.url)
        } else {
            runThenOpen(tool("mulmoclaude-start"), url: mcMode.url)
        }
    }
    func startMT() { run(tool("mulmoterminal-start"), label: "MulmoTerminalを起動中") }
    func stopMT() { run(tool("mulmoterminal-stop"), label: "MulmoTerminalを停止中") }
    func restartMT() { run(tool("mulmoterminal-restart"), label: "MulmoTerminalを再起動中") }
    func checkUpdate() { run(tool("mulmoterminal-check-update"), label: "更新を確認中") }
    func checkAllUpdates() {
        run("""
        \(tool("mulmo-check-updates"))
        \(tool("mulmo-control-self-update")) check
        \(tool("mulmo-check-claude-login"))
        \(tool("mulmo-check-remote-host"))
        """, label: "更新を確認中")
    }

    /// エージェントのスマホ連携（Issue #160）。
    ///
    /// Claude Code は初回のフォルダだけ、スクリプトがターミナルを開いて信頼確認を
    /// 出す。そこは人が踏むところなので、こちらでは代われない。
    func startClaudeRemote() {
        run("\(tool("mulmo-claude-remote")) start", label: "スマホ連携（Claude Code）を繋いでいます")
    }

    func stopClaudeRemote() {
        run("\(tool("mulmo-claude-remote")) stop", label: "スマホ連携（Claude Code）を止めています")
    }

    /// 立てたセッションの入口を開く。**押す先が無いときはボタン自体を出さない**
    /// ので、ここに来るのは URL があるときだけ。
    func openClaudeRemote() {
        openURL(claudeRemote.openURL)
    }

    func startCodexRemote() {
        run("\(tool("mulmo-codex-remote")) start", label: "スマホ連携（Codex）を繋いでいます")
    }

    func stopCodexRemote() {
        run("\(tool("mulmo-codex-remote")) stop", label: "スマホ連携（Codex）を止めています")
    }

    /// スマホと繋ぐための短命なコードを出す。**ログには残さない。**
    func pairCodexRemote() {
        run("\(tool("mulmo-codex-remote")) pair", label: "ペアリングコードを出しています")
    }

    /// 切れたスマホ連携を繋ぎ直す。初回接続はブラウザでの Google サインインが
    /// 要る（idToken が作れない）ので、そちらは画面への案内に留める。
    ///
    /// 鍵を預かっていれば、MulmoTerminal が止まっていても繋げる（Issue #154）。
    /// その場合は起動を待つ分だけ長くかかるので、表示は「繋いでいます」にする。
    func reconnectRemoteHost() {
        run(tool("mulmo-remote-host-reconnect"),
            label: remoteHost.canConnectFromControl
                ? "スマホ連携（MulmoTerminal）を繋いでいます"
                : "スマホ連携（MulmoTerminal）を繋ぎ直しています")
    }

    /// チャット側は接続が別なので、繋ぎ直す口も別（Issue #23）。片方だけ切れる。
    ///
    /// 鍵を預かっていれば、MulmoClaude が止まっていても繋げる（Issue #145）。
    /// その場合は起動を待つ分だけ長くかかるので、表示は「繋いでいます」にする。
    func reconnectMCRemoteHost() {
        run(tool("mulmoclaude-remote-host-reconnect"), label: "スマホ連携（MulmoClaude）を繋いでいます")
    }

    /// ログインし直す入口まで連れて行く。ブラウザでのサインインは本人がやる
    /// （OAuth なのでアプリが代われない）。
    ///
    /// 以前は AppleScript でターミナルを操作していたが、オートメーションの許可が
    /// 無い環境では**必ず**失敗する（実測 2026-09-03: 押してもデスクトップに戻るだけ）。
    /// ターミナルが標準で開いて実行してくれる .command ファイルなら許可が要らない。
    /// `claude /login` まで書いておくので、本人が打つのはブラウザのサインインだけ。
    func openClaudeLogin() {
        let command = "cd \(shellQuoted(mulmoClaudeDir)) && claude /login"
        let script = """
        #!/bin/zsh
        PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        \(command)
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mulmo-claude-login.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            showMessage(
                title: "ターミナルを開けませんでした",
                text: "ターミナルで次を実行してください:\n\(command)"
            )
            return
        }
        NSWorkspace.shared.open(url)
        showMessage(
            title: "ターミナルを開きました",
            text: "ブラウザが開いたらサインインしてください。開かなければ、そのターミナルで /login と入力します。"
        )
    }
    func updateSelfApp() {
        run("\(tool("mulmo-control-self-update")) apply", label: "Mulmo Controlを更新中")
    }
    func updateMT() {
        prepareUpdateReport(
            title: "MulmoTerminalを更新しました",
            items: updateItems.filter { $0.id == "mulmoterminal" && $0.status == "update" }
        )
        run(updateCommand(tool("mulmoterminal-update-latest")), label: "MulmoTerminalを更新中")
    }
    func installMT() { run(tool("mulmoterminal-update-latest"), label: "MulmoTerminalをインストール中") }
    func installFamily(_ package: FamilyPackage) {
        guard package.isInstallable else {
            showMessage(title: "\(package.title)はまだ未対応です", text: "npmで公開されていないため、この画面からはインストールできません。")
            return
        }
        guard let npmPath else {
            showMessage(title: "npmが見つかりません", text: "先にNode.jsをインストールしてください。")
            return
        }
        let prefix = familyPrefix
        let binPath = "\(prefix)/node_modules/.bin/\(package.commandName)"
        run("""
        mkdir -p "\(prefix)" "\(localBin)" /private/tmp/npm-cache-mulmo-control
        MULMO_NPM="\(npmPath)" \(tool("mulmo-npm-install")) "\(prefix)" "\(package.packageName)@latest"
        if [ -x "\(binPath)" ]; then /bin/ln -sf "\(binPath)" "\(localBin)/\(package.commandName)"; fi
        """, label: "\(package.title)をインストール中")
    }
    func updateInstalledFamily() {
        let packages = familyPackages.filter { $0.isInstallable && familyCommandPath($0) != nil }
        guard !packages.isEmpty else {
            showMessage(title: "追加ツールは未導入です", text: "先に追加タブからインストールしてください。")
            return
        }
        guard let command = familyInstallCommand(for: packages) else { return }
        prepareUpdateReport(
            title: "追加ツールを更新しました",
            items: updateItems.filter { item in
                item.status == "update" && packages.contains(where: { $0.id == item.id || $0.packageName == item.name })
            }
        )
        run(updateCommand(command), label: "追加ツールをまとめて更新中")
    }
    func updateAllInstalled() {
        var commands: [String] = []
        // 実際に走らせるコマンドと同じ範囲で報告する。未導入の物は更新していないので載せない。
        var updated: [FamilyPackage] = []
        var updatedIds: Set<String> = []
        if mtInstalled {
            commands.append(tool("mulmoterminal-update-latest"))
            updatedIds.insert("mulmoterminal")
        }
        if mcInstalled {
            commands.append(tool("mulmoclaude-update-latest"))
            updatedIds.insert("mulmoclaude")
        }
        let installedFamily = familyPackages.filter { $0.isInstallable && familyCommandPath($0) != nil }
        if let familyCommand = familyInstallCommand(for: installedFamily) {
            commands.append(familyCommand)
            updated = installedFamily
        }
        guard !commands.isEmpty else {
            showMessage(title: "更新対象がありません", text: "先にインストールしてください。")
            return
        }
        prepareUpdateReport(
            title: "一括更新しました",
            items: updateItems.filter { item in
                guard item.status == "update" else { return false }
                if updatedIds.contains(item.id) { return true }
                return updated.contains(where: { $0.id == item.id || $0.packageName == item.name })
            }
        )
        run(updateCommand(commands.joined(separator: "\n")), label: "まとめて更新中")
    }
    /// モードを切り替える（Issue #168）。
    ///
    /// 動いている最中に切り替えたら起こし直す。待つポートが変わるので、
    /// 古いモードのまま動かし続けると画面には新しいモードが出ているのに
    /// 「停止中」と表示され、`開く` も居ない側を開く。
    func setMCMode(_ mode: MulmoClaudeMode) {
        guard mode != mcMode else { return }
        writeMulmoClaudeMode(mode)
        mcMode = mode
        if mcRunning {
            restartMC()
        } else {
            actionText = "\(mode.label)に切り替えました"
        }
    }

    func startMC() { run(tool("mulmoclaude-start"), label: "MulmoClaudeを起動中") }
    func stopMC() { run(tool("mulmoclaude-stop"), label: "MulmoClaudeを停止中") }
    func restartMC() { run(tool("mulmoclaude-restart"), label: "MulmoClaudeを再起動中") }
    func updateMC() {
        prepareUpdateReport(
            title: "MulmoClaudeを更新しました",
            items: updateItems.filter { $0.id == "mulmoclaude" && $0.status == "update" }
        )
        run(updateCommand(tool("mulmoclaude-update-latest")), label: "MulmoClaudeを更新中")
    }
    func openMCRepo() { openURL(mulmoClaudeRepo) }
    func openReleases() { openURL(mulmoControlReleases) }

    func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(homeDir)/.mulmoterminal/logs"))
    }

    func openMCLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logDir))
    }

    func openActionLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: actionLogPath))
    }

    private func familyCommandPath(_ package: FamilyPackage) -> String? {
        if let path = cachedCommandPath(package.commandName) {
            return path
        }
        let localPath = "\(localBin)/\(package.commandName)"
        if FileManager.default.isExecutableFile(atPath: localPath) {
            return localPath
        }
        let projectPath = "\(mulmoClaudeDir)/node_modules/.bin/\(package.commandName)"
        if FileManager.default.isExecutableFile(atPath: projectPath) {
            return projectPath
        }
        return nil
    }

    private func familyInstallCommand(for packages: [FamilyPackage]) -> String? {
        guard !packages.isEmpty else { return nil }
        guard let npmPath else {
            showMessage(title: "npmが見つかりません", text: "先にNode.jsをインストールしてください。")
            return nil
        }
        let prefix = familyPrefix
        let installLines = packages.map { package in
            let binPath = "\(prefix)/node_modules/.bin/\(package.commandName)"
            return """
            MULMO_NPM="\(npmPath)" \(tool("mulmo-npm-install")) "\(prefix)" "\(package.packageName)@latest"
            if [ -x "\(binPath)" ]; then /bin/ln -sf "\(binPath)" "\(localBin)/\(package.commandName)"; fi
            """
        }.joined(separator: "\n")
        return """
        mkdir -p "\(prefix)" "\(localBin)" /private/tmp/npm-cache-mulmo-control
        \(installLines)
        """
    }

    private func updateCommand(_ command: String) -> String {
        // 更新本体の終了コードを持ち越す。後ろの mulmo-check-updates が最後になると、
        // 更新が失敗していても全体が成功扱いになり、run() の失敗処理が働かない。
        """
        rc=0
        (
        \(command)
        ) || rc=$?
        \(tool("mulmo-check-updates"))
        \(releaseSummaryCommand())
        \(tool("mulmo-release-notes")) || true
        exit $rc
        """
    }

    private func releaseSummaryCommand() -> String {
        guard let items = pendingUpdateReport, !items.isEmpty else {
            return ": > \"\(lastUpdateSummaryPath)\""
        }
        let payload = items
            .map { "\($0.id)\t\($0.displayName)\t\($0.latest)" }
            .joined(separator: "\n")
        let encoded = Data(payload.utf8).base64EncodedString()
        return "MULMO_RELEASE_ITEMS_B64=\"\(encoded)\" \(tool("mulmo-release-summary")) || true"
    }

    /// 失敗の一行を作る。理由が取れないときだけ、これまでの文言に落ちる。
    static func failureText(prefix: String = "失敗しました") -> String {
        guard let detail = lastLineOfActionLog() else {
            return "\(prefix)。ログを確認してください"
        }
        return "\(prefix): \(detail)"
    }

    private func run(_ command: String, label: String? = nil) {
        actionText = label
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "mkdir -p \"\(logDir)\"\n(\n\(command)\n) >\"\(actionLogPath)\" 2>&1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "failed: \(error)\n".write(toFile: actionLogPath, atomically: true, encoding: .utf8)
            }
            let succeeded = process.terminationStatus == 0
            await MainActor.run {
                self.refreshAfterAction()
                // 終了コードが非0でも報告は出す。一部だけ失敗したときに黙って
                // 消すと、上がった物まで無かったことになる。何が動いて何が
                // 動かなかったかは、更新後の実測値が知っている。
                self.recordPendingUpdateReport()
                self.actionText = succeeded ? nil : Self.failureText()
            }
        }
    }

    private func checkUpdatesSilentlyIfNeeded(force: Bool = false) {
        guard !automaticUpdateCheckRunning else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastAutomaticUpdateCheck) > 21_600 else { return }

        lastAutomaticUpdateCheck = now
        automaticUpdateCheckRunning = true
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [
                "-lc",
                """
                \(tool("mulmo-check-updates"))
                \(tool("mulmo-control-self-update")) check
                \(tool("mulmo-check-claude-login"))
                \(tool("mulmo-check-remote-host"))
                """
            ]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "silent update check failed: \(error)\n".write(toFile: actionLogPath, atomically: true, encoding: .utf8)
            }
            await MainActor.run {
                self.automaticUpdateCheckRunning = false
                self.refreshAfterAction()
            }
        }
    }

    private func runThenOpen(_ command: String, url: String) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "mkdir -p \"\(logDir)\"\n(\n\(command)\n) >\"\(actionLogPath)\" 2>&1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "failed: \(error)\n".write(toFile: actionLogPath, atomically: true, encoding: .utf8)
            }
            let succeeded = process.terminationStatus == 0
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                self.refreshAfterAction()
                if succeeded {
                    self.actionText = nil
                    self.openURL(url)
                } else {
                    self.actionText = Self.failureText(prefix: "起動に失敗しました")
                }
            }
        }
    }

    private func runThenOpenFile(_ command: String, filePath: String, label: String? = nil) {
        actionText = label
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "mkdir -p \"\(logDir)\"\n(\n\(command)\n) >\"\(actionLogPath)\" 2>&1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "failed: \(error)\n".write(toFile: actionLogPath, atomically: true, encoding: .utf8)
            }
            await MainActor.run {
                self.refreshAfterAction()
                self.actionText = nil
                NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
            }
        }
    }

    private func openURL(_ value: String) {
        if let url = URL(string: value) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showMessage(title: String, text: String) {
        notice = NoticeMessage(title: title, text: text)
    }

    private func prepareUpdateReport(title: String, items: [MulmoUpdateItem]) {
        pendingUpdateReportTitle = title
        pendingUpdateReport = items
        // 前回の理由が残っていると、今回の結果として読まれてしまう。
        try? FileManager.default.removeItem(atPath: updateReasonsPath)
        // 走らせる前の実測値を控える。報告はこれと更新後の値の差で作る。
        // 「これから上がるはずの版」を報告に使うと、上がらなかった物まで
        // 上がったことになってしまう。
        beforeVersions = Dictionary(
            updateItems.map { ($0.id, $0.current) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// 更新スクリプトが書き置いた理由を id ごとに読む（`id<TAB>理由`）。
    /// 同じ id が複数あれば、最後に書かれたものを採る。
    private func readUpdateReasons() -> [String: String] {
        guard let text = try? String(contentsOfFile: updateReasonsPath, encoding: .utf8) else { return [:] }
        var reasons: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            reasons[String(parts[0])] = String(parts[1])
        }
        return reasons
    }

    /// 更新後に実測し、動いた物と動かなかった物を分けて返す。
    private func measureUpdateOutcome() -> (moved: [String], stalled: [String]) {
        guard let attempted = pendingUpdateReport else { return ([], []) }
        let reasons = readUpdateReasons()
        var moved: [String] = []
        var stalled: [String] = []
        for item in attempted {
            let before = beforeVersions[item.id] ?? item.current
            let after = updateItems.first(where: { $0.id == item.id })?.current ?? before
            if after != before {
                moved.append("\(item.displayName): \(before) → \(after)")
            } else if let reason = reasons[item.id] {
                stalled.append("\(item.displayName): \(before) のまま — \(reason)")
            } else {
                stalled.append("\(item.displayName): \(before) のまま")
            }
        }
        return (moved, stalled)
    }

    private func recordPendingUpdateReport() {
        guard pendingUpdateReport != nil else { return }
        let outcome = measureUpdateOutcome()
        let title: String
        if outcome.moved.isEmpty {
            title = "更新できませんでした"
        } else if outcome.stalled.isEmpty {
            title = pendingUpdateReportTitle ?? "更新しました"
        } else {
            title = "一部だけ更新しました"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d H:mm"

        var lines: [String] = []
        if !outcome.moved.isEmpty {
            lines.append(contentsOf: outcome.moved)
        }
        if !outcome.stalled.isEmpty {
            lines.append("更新されなかったもの:")
            lines.append(contentsOf: outcome.stalled)
            // 理由が1つも取れなかったときだけログの場所を出す。理由が書いてある
            // のにログへ誘導すると、読まなくていいものを読ませることになる
            // （Issue #46）。
            if !outcome.stalled.contains(where: { $0.contains(" — ") }) {
                lines.append("ログ: \(logDir)")
            }
        }
        let detail = lines.isEmpty ? "変更内容は確認できませんでした" : lines.joined(separator: "\n")

        let summary = outcome.moved.isEmpty ? "" : readLastUpdateSummary()
        let noticeText = [detail, summary]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let report = [formatter.string(from: Date()), detail, summary]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        lastUpdateReport = report
        notice = NoticeMessage(title: title, text: noticeText)
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: lastUpdateReportPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? report.write(toFile: lastUpdateReportPath, atomically: true, encoding: .utf8)
        pendingUpdateReport = nil
        pendingUpdateReportTitle = nil
        beforeVersions = [:]
    }

    /// ログイン時に Mulmo Control 自身を立ち上げるか（Issue #60）。
    ///
    /// メニューバーに常駐するアプリなのに、再起動すると居なくなっていた。
    /// これまで動いていたのは、利用者が SwiftBar 時代に手で置いた LaunchAgent が
    /// 残っていたからで、アプリ名を変えたときに追随せず壊れていた。配った人には
    /// そもそもその仕組みが無い。
    ///
    /// SMAppService.mainApp を使う。システム設定の「一般 → ログイン項目」に
    /// 出るので、切りたい人が自分で切れる。plist を置く必要もない。
    ///
    /// 既定はオン。ただし黙って入れるのではなく、入れたことを1回だけ知らせる
    /// （Issue #75）。
    ///
    /// もともと既定オフだったが、それは選択として成立していなかった。この
    /// アプリはメニューバーに常駐して初めて機能する。更新の確認も各種ボタンも、
    /// そこにいなければ届かない。オフは選択肢ではなく、機能しない状態でしかない。
    /// 実際、利用者は Mac を再起動したあと Mulmo Control が出てこず、手で開き
    /// 直していた。
    ///
    /// 実機で他のツールを見ると、ログイン項目に入っているのは Raycast と Steam
    /// だけで、Docker / Slack / Zoom は入っていない。ただし前者は「常駐して
    /// 初めて意味があるもの」、後者は「使いたいときに自分で開くもの」で、
    /// このアプリは前者。
    ///
    /// 質問にはしない。断る人がほぼいない選択を尋ねるのは、無意味な判断を
    /// 1回増やすだけ。macOS 13 以降はシステム設定の「一般 → ログイン項目」に
    /// 必ず出るので、こっそり入れることにはならない。
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// 手で置かれた LaunchAgent。SwiftBar 時代の名残で、同じラベルを使っている
    /// 人がいる（作者がそうだった）。両方を有効にすると、ログイン時に2つの経路から
    /// 起動されることになる。気づける形にしておく。
    private var legacyLoginAgent: String {
        "\(homeDir)/Library/LaunchAgents/com.shutanuma.mulmocontrol.plist"
    }
    var hasLegacyLoginAgent: Bool { FileManager.default.fileExists(atPath: legacyLoginAgent) }

    /// ログイン項目の登録は macOS が拒むことがある（利用者が設定で切った直後など）。
    /// 黙って失敗すると、押したのに変わらない画面になるので理由を出す。
    /// 古い設定は、見つけたらこちらで外す。
    ///
    /// 以前は「次を削除してください」とパスを出していたが、ターミナルを開かせ
    /// ないのがこのアプリの役目なので、パスを渡して終わるのは筋が通らない。
    /// 役目は同じで、残すと二重に起動するだけのものなので、消して困るものが無い。
    @discardableResult
    private func removeLegacyLoginAgentIfNeeded() -> Bool {
        guard hasLegacyLoginAgent else { return false }
        let label = "com.shutanuma.mulmocontrol"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        try? task.run()
        task.waitUntilExit()
        try? FileManager.default.removeItem(atPath: legacyLoginAgent)
        return true
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if removeLegacyLoginAgentIfNeeded() {
                    showMessage(
                        title: "ログイン時に開くようにしました",
                        text: "同じ役目の古い設定が残っていたので、二重に起動しないよう外しました。やめる場合はシステム設定の「一般 → ログイン項目」から切り替えられます。"
                    )
                }
            }
        } catch {
            showMessage(
                title: "ログイン時の起動を切り替えられませんでした",
                text: "システム設定の「一般 → ログイン項目」から Mulmo Control を切り替えてください。\n\n\(errorText(error))"
            )
        }
        objectWillChange.send()
    }

    private func errorText(_ error: Error) -> String {
        let ns = error as NSError
        return ns.localizedDescription.isEmpty ? "\(ns.domain) \(ns.code)" : ns.localizedDescription
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.enableLaunchAtLoginOnFirstRunIfNeeded(granted: granted)
                self.announceFirstLaunchIfNeeded(granted: granted)
                self.announceModeDefaultIfNeeded()
            }
        }
    }

    /// 1回だけ、ログイン時起動を有効にして、そう伝える（Issue #75）。
    ///
    /// 印は専用の鍵にする。初回アナウンス（#9）の鍵に相乗りすると、既に一度でも
    /// 起動したことがある人には永遠に効かない。ここは既存の利用者にも1回だけ
    /// 効いてほしい。
    ///
    /// 自分で切った人の意思は必ず残す。印を先に立てるので、切ったあとに再び
    /// 有効化されることはない。
    private func enableLaunchAtLoginOnFirstRunIfNeeded(granted: Bool) {
        let key = "mulmo-control.launch-at-login-defaulted"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !launchAtLogin else { return }

        do {
            try SMAppService.mainApp.register()
        } catch {
            // ここで理由を出しても、初回の利用者には手の打ちようがない。
            // 設定画面の行から自分で押せるので、黙って諦める。
            return
        }
        let removed = removeLegacyLoginAgentIfNeeded()
        objectWillChange.send()

        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "ログイン時に開くようにしました"
        content.body = removed
            ? "同じ役目の古い設定も外しました。やめる場合はシステム設定の「一般 → ログイン項目」から切り替えられます"
            : "やめる場合はシステム設定の「一般 → ログイン項目」から切り替えられます"
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "mulmo-control-launch-at-login", content: content, trigger: nil)
        )
    }

    /// 初回だけ「メニューバーに入りました」と知らせる（Issue #9）。
    ///
    /// このアプリはウィンドウも Dock アイコンも出さないので、初回は本当に何も
    /// 起きていないように見える。最初の外部利用者が「起動できない」と報告した
    /// ときも、実際はインストールの失敗だったが、成功していても気づけなかった。
    ///
    /// npx で入れた人には特に効く。install.sh はダイアログを出すが、npx は
    /// 端末に文字を出すだけで、ターミナルの出力を読まない人こそこのアプリの
    /// 対象なので。
    ///
    /// 印は UserDefaults に置く。issue には app-info.env に置く案が書かれて
    /// いたが、あれは install.sh が毎回書き直すので、更新のたびに通知が
    /// 再発してしまう。
    /// 既定が通常モードに変わったことを、一度だけ知らせる（Issue #174）。
    ///
    /// 相手は「自分でモードを選んだことがない人」= 設定ファイルを持たない人。
    /// 黙って変えると、開くアドレスが 3001 に変わった理由が誰にも分からない。
    /// **気づく手がかりが1つも無かったこと自体が #174 の中身**なので、ここで
    /// 黙るのは同じ過ちを繰り返すことになる。
    ///
    /// 印は UserDefaults。`app-info.env` は install.sh が更新のたびに書き直すので、
    /// そこに置くと更新のたびに再発する（初回アナウンスと同じ理由）。
    private func announceModeDefaultIfNeeded() {
        let key = "mulmo-control.mode-default-announced"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        // 自分で選んでいる人には、何も変わっていない。
        guard !MulmoClaudeMode.chosen else { return }
        notice = NoticeMessage(
            title: "MulmoClaude の起動のしかたが変わりました",
            text: "これまでは開発者向けのモードで起動していました。作業中に画面が勝手に更新され、"
                + "入力中の文字や貼った画像が消えることがあったのは、そのためです。"
                + "これからは通常モードで起動します。開くアドレスは 3001 に変わります。"
                + "元に戻すときは、MulmoClaude の「モード」から。"
        )
    }

    private func announceFirstLaunchIfNeeded(granted: Bool) {
        let key = "mulmo-control.first-launch-announced"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        // 通知を出せたかに関わらず印を付ける。出せなかったからと言って毎回
        // 試すと、許可しなかった人に許可を求め続けることになる。
        UserDefaults.standard.set(true, forKey: key)
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Mulmo Control をメニューバーに追加しました"
        content.body = "画面いちばん上の帯の右のほう、時計や Wi-Fi の並びにある >_ アイコンから操作できます"
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "mulmo-control-first-launch", content: content, trigger: nil)
        )
    }

    private func notifyIfNeeded(for items: [MulmoUpdateItem]) {
        let updates = items.filter { $0.status == "update" }
        guard !updates.isEmpty else { return }

        let key = updates
            .map { "\($0.id):\($0.current)->\($0.latest)" }
            .sorted()
            .joined(separator: "|")
        guard key != notifiedUpdateKey else { return }

        let names = updates.map { $0.displayName }.joined(separator: "、")
        let content = UNMutableNotificationContent()
        content.title = "Mulmo の更新があります"
        content.body = names
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mulmo-control-updates-\(abs(key.hashValue))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            guard error == nil else { return }
            UserDefaults.standard.set(key, forKey: "mulmo-control.notified-update-key")
            Task { @MainActor in
                self.notifiedUpdateKey = key
            }
        }
    }

    private func notifyClaudeLoginIfNeeded(_ status: ClaudeLoginStatus) {
        guard status.isExpired else {
            // 直ったら、次に切れたときにまた知らせる。
            if notifiedClaudeLoginAt != nil {
                UserDefaults.standard.removeObject(forKey: "mulmo-control.notified-claude-login-at")
                notifiedClaudeLoginAt = nil
            }
            return
        }
        guard status.checkedAt != notifiedClaudeLoginAt, notifiedClaudeLoginAt == nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude のログインが切れています"
        content.body = "MulmoClaude のチャットが使えません。メニューバーから復旧できます"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mulmo-control-claude-login",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            guard error == nil else { return }
            UserDefaults.standard.set(status.checkedAt, forKey: "mulmo-control.notified-claude-login-at")
            Task { @MainActor in
                self.notifiedClaudeLoginAt = status.checkedAt
            }
        }
    }

    private func notifySelfUpdateIfNeeded(_ status: SelfUpdateStatus) {
        guard status.status == "update" else { return }
        let key = "\(status.installedVersion)->\(status.latestVersion)"
        guard key != notifiedSelfUpdateKey else { return }

        let content = UNMutableNotificationContent()
        content.title = "Mulmo Control の更新があります"
        content.body = "メニューバーからアプリ更新できます"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mulmo-control-self-update-\(abs(key.hashValue))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            guard error == nil else { return }
            UserDefaults.standard.set(key, forKey: "mulmo-control.notified-self-update-key")
            Task { @MainActor in
                self.notifiedSelfUpdateKey = key
            }
        }
    }
}

@main
struct MulmoControlApp: App {
    @StateObject private var model = ControlModel()

    /// ホバーガイドの応答口（Issue #185）。ポートが塞がっていれば黙って諦める。
    init() { GuideServer.shared.start() }

    var body: some Scene {
        MenuBarExtra {
            ControlView(model: model)
                .frame(width: 370)
                // 開いている間だけ細かく巡回する。閉じている間も5秒ごとに外部
                // プロセスを起動し続けていて、macOS に「エネルギーを著しく消費中」
                // と言われていた（Issue #38）。
                .onAppear { model.setPanelOpen(true) }
                .onDisappear { model.setPanelOpen(false) }
        } label: {
            Image(systemName: model.menuIconName)
                .font(AppFont.section)
                // 状態を文字で持たない（Issue #112）。以前は `MT on / MC off` を
                // ここに渡していたが、accessibilityLabel は画面に出ないため、
                // 読み手のいない値を組み立てて直し続けることになっていた。
                // 状態は画面を開けば分かる。ここは名前だけでよい。
                .accessibilityLabel("Mulmo Control")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ControlView: View {
    @ObservedObject var model: ControlModel
    @State private var screen: ControlScreen = .operate

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            if let actionText = model.actionText {
                HStack(spacing: 8) {
                    // 終わって失敗した後も回していたので、まだ動いているように
                    // 見えていた（Issue #162）。回すのは動いている間だけ。
                    if !actionText.contains("失敗") {
                        ProgressView()
                            .scaleEffect(0.62)
                    }
                    Text(actionText)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.secondaryText)
                    Spacer()
                    if actionText.contains("失敗") {
                        Button("ログ", action: model.openActionLog)
                            .buttonStyle(.plain)
                            .font(AppFont.action)
                            .foregroundStyle(Palette.accentText)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if model.claudeLogin.isExpired {
                ClaudeLoginCard(model: model)
            }
            if let notice = model.notice {
                NoticeCard(notice: notice) {
                    model.notice = nil
                }
            }
            TopTabs(selection: $screen)
            UpdateToolbar(model: model)
            Hairline()
            switch screen {
            case .operate:
                OperateView(model: model)
            case .family:
                FamilyView(model: model) { package in
                    model.installFamily(package)
                    screen = .operate
                }
            case .environment:
                EnvironmentView(model: model)
            }
            Hairline()
            HStack {
                Spacer()
                FooterButton(title: "終了", systemImage: "xmark.square", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(AppFont.section)
                    .foregroundStyle(Palette.accentText)
                    .frame(width: 30, height: 30)
                    .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mulmo Control")
                        .font(AppFont.appTitle)
                        .foregroundStyle(Palette.primaryText)
                    Text(model.updateSummary)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
    }
}

enum ControlScreen: String, CaseIterable, Identifiable {
    case operate = "運用"
    case family = "追加"
    case environment = "環境"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .operate:
            return "play.rectangle"
        case .family:
            return "square.grid.2x2"
        case .environment:
            return "gearshape"
        }
    }
}

struct TopTabs: View {
    @Binding var selection: ControlScreen

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ControlScreen.allCases) { screen in
                Button {
                    selection = screen
                } label: {
                    VStack(spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: screen.systemImage)
                                .font(AppFont.tab)
                            Text(screen.rawValue)
                                .font(AppFont.tab)
                        }
                        Rectangle()
                            .fill(selection == screen ? Color.white.opacity(0.82) : Palette.hairline)
                            .frame(width: 46, height: 2)
                    }
                    .foregroundStyle(selection == screen ? Color.white : Palette.secondaryText)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(selection == screen ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // .buttonStyle(.plain) の当たり判定は描画された中身に従うので、
                    // 未選択のタブ（背景が Color.clear）は文字とアイコンの上でしか
                    // 反応しなかった。押したいのは常に未選択のタブなので、余白ごと
                    // 当たるように形を明示する（Issue #34）。
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 直近のリリースの内容を、その場で読めるようにする（Issue #176）。
///
/// 更新を勧めておいて中身を見せないのは筋が悪い。v1.0.61 では MulmoClaude の
/// 開くアドレスが 5173 から 3001 に変わったが、その理由と戻し方はリリース
/// ノートにしか無く、アプリからは辿り着けなかった。
///
/// **控えが無くても口を閉じない。** ネットが無い / GitHub が落ちている / API の
/// 上限に当たった、のいずれでも「読めません」と言いながら GitHub へ飛ぶボタン
/// は出す。取得を前提に画面を組むと、繋がらない日にいちばん困る人が行き先を
/// 失う。
/// リリースノートの本文を組み直す（Issue #178）。
///
/// 素通しで `Text` に渡すと `##` と `**` とバッククォートがそのまま出る。行も
/// 元のノートが80桁で折ってあるぶんと画面幅の折り返しが二重にかかって、文の
/// 途中で切れて見える。
///
/// **Markdown を全部解釈しようとしない。** 実際にノートで使っているのは見出し・
/// 箇条書き・強調・インラインコードの4つだけで、使っていない記法のために
/// 壊れやすい実装を持つ理由が無い。
struct ReleaseNotesBody: View {
    let text: String

    /// 段落単位に畳む。空行が区切り、段落の中の改行は空白にする（元のノートは
    /// 80桁で折ってあるので、畳まないと画面幅と二重に折り返される）。
    private var blocks: [(id: Int, kind: Kind, text: String)] {
        enum State { case none }
        var result: [(id: Int, kind: Kind, text: String)] = []
        var paragraph: [String] = []
        func flush() {
            guard !paragraph.isEmpty else { return }
            result.append((result.count, .paragraph, paragraph.joined(separator: " ")))
            paragraph = []
        }
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }
            if let heading = line.range(of: "^#{1,6}[ \t]+", options: .regularExpression) {
                flush()
                result.append((result.count, .heading, String(line[heading.upperBound...])))
                continue
            }
            if let bullet = line.range(of: "^[-*][ \t]+", options: .regularExpression) {
                flush()
                result.append((result.count, .bullet, String(line[bullet.upperBound...])))
                continue
            }
            paragraph.append(line)
        }
        flush()
        return result
    }

    enum Kind { case heading, bullet, paragraph }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks, id: \.id) { block in
                switch block.kind {
                case .heading:
                    Text(inline(block.text))
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                        .padding(.top, block.id == 0 ? 0 : 4)
                case .bullet:
                    HStack(alignment: .top, spacing: 6) {
                        Text("・").foregroundStyle(Palette.secondaryText)
                        Text(inline(block.text))
                    }
                    .font(AppFont.small)
                    .foregroundStyle(Palette.primaryText)
                case .paragraph:
                    Text(inline(block.text))
                        .font(AppFont.small)
                        .foregroundStyle(Palette.primaryText)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 強調とインラインコードだけ。解釈できない書き方が来たら、記号を落として
    /// 素の文字にする — 記号が出るよりは読める。
    private func inline(_ source: String) -> AttributedString {
        if let parsed = try? AttributedString(markdown: source) { return parsed }
        return AttributedString(source.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: ""))
    }
}

struct ReleaseNotesButton: View {
    @ObservedObject var model: ControlModel
    @State private var showsDetail = false

    var body: some View {
        Button("リリースノート") {
            showsDetail.toggle()
        }
        .buttonStyle(.plain)
        .font(AppFont.action)
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Palette.controlFill, in: Capsule())
        .popover(isPresented: $showsDetail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if let notes = model.releaseNotes {
                    // 版番号だけでは、何の版か分からない（Issue #178）。同じ画面に
                    // MulmoCast / MulmoCast Vision / MulmoBridge CLI の版が並んで
                    // いるので、アプリ名まで書いて初めて特定できる。
                    HStack(spacing: 6) {
                        Text("Mulmo Control \(notes.tag)")
                            .font(AppFont.section)
                            .foregroundStyle(Palette.primaryText)
                        Text(notes.date)
                            .font(AppFont.small)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    ScrollView {
                        ReleaseNotesBody(text: notes.body)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 280)
                } else {
                    Text("リリースノート")
                        .font(AppFont.section)
                        .foregroundStyle(Palette.primaryText)
                    Text("まだ読み込めていません。`確認` を押すと取りに行きます。繋がらないときは GitHub で読めます。")
                        .font(AppFont.small)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("GitHub で見る") {
                    model.openReleases()
                    showsDetail = false
                }
                .buttonStyle(.plain)
                .font(AppFont.action)
                .foregroundStyle(Palette.accentText)
            }
            .padding(14)
            .frame(width: 320)
        }
    }
}

struct UpdateToolbar: View {
    @ObservedObject var model: ControlModel
    @State private var skidOffset: CGFloat = 0
    @State private var skidAngle: Double = 0

    private var updateTargets: [MulmoUpdateItem] {
        model.updateItems.filter { $0.status == "update" }
    }

    private var hasSelfUpdate: Bool {
        model.selfUpdate.status == "update"
    }

    private var isUnknown: Bool {
        (model.updateItems.isEmpty || model.updateSummary.contains("未確認")) && model.selfUpdate.status == "unknown"
    }

    private var statusTitle: String {
        if hasSelfUpdate || !updateTargets.isEmpty {
            return "更新あり"
        }
        if isUnknown {
            return "未確認"
        }
        return "最新"
    }

    private var statusDetail: String {
        if hasSelfUpdate || !updateTargets.isEmpty {
            var names = updateTargets.map(\.displayName)
            if hasSelfUpdate {
                names.insert("Mulmo Control", at: 0)
            }
            return names.joined(separator: "、")
        }
        if isUnknown {
            return "通知前にここで確認できます"
        }
        return "更新が出たら通知します"
    }

    private var statusColor: Color {
        if hasSelfUpdate || !updateTargets.isEmpty {
            return Palette.warn
        }
        if isUnknown {
            return Palette.secondaryText
        }
        return Palette.ok
    }

    // 文字は上、ボタンは下の行（Issue #180）。
    //
    // 以前は横一列に詰めていた。ボタンが増えるたびに文字の幅が削られ、#176 で
    // `リリースノート` を足した時点で「更新が出たら通知します」が
    // 「更新が出たら通知し…」になった。`アプリ更新` が出る日はもう1つ増えるので、
    // **更新の中身を読ませたいときにいちばん削られる**。逆になっていた。
    //
    // サービスのパネル（ServicePanel）は元からこの組み方で、帯だけが違っていた。
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    // 切り詰めない。入り切らないときに捨てられるのは、
                    // 「何が更新されるか」の一覧そのものになる。
                    Text(statusDetail)
                        .font(AppFont.small)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button("確認", action: model.checkAllUpdates)
                    .buttonStyle(.plain)
                    .font(AppFont.action)
                    .foregroundStyle(isUnknown ? .white : Palette.secondaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(isUnknown ? Palette.accent : Palette.controlFill, in: Capsule())
                ReleaseNotesButton(model: model)
                if hasSelfUpdate || !updateTargets.isEmpty {
                    Button(hasSelfUpdate ? "アプリ更新" : "一括更新") {
                        if hasSelfUpdate {
                            model.updateSelfApp()
                        } else {
                            model.updateAllInstalled()
                        }
                    }
                        .buttonStyle(.plain)
                        .font(AppFont.action)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Palette.accent, in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .offset(x: skidOffset)
        .rotationEffect(.degrees(skidAngle), anchor: .bottomLeading)
        .onAppear { skidIfNeeded() }
        .onChange(of: updateKey) { _, _ in skidIfNeeded() }
    }

    // ── 「更新あり」が出た瞬間だけ滑り込ませる ──────────────────
    //
    // 開くたびに動かすと、更新を当てるまでの数日間ずっと動き続けて邪魔になる。
    // 同じ更新に対しては一度きりにする。
    //
    // 印は専用の鍵で持つ。通知の鍵（notified-update-key）に相乗りすると、
    // 通知を許可していない人には永遠に動かない（#75 で踏んだ形と同じ）。
    private var updateKey: String {
        var parts = updateTargets.map { "\($0.id):\($0.current)->\($0.latest)" }
        if hasSelfUpdate {
            parts.append("mulmo-control:\(appVersion)->\(model.selfUpdate.latestVersion)")
        }
        return parts.sorted().joined(separator: "|")
    }

    private func skidIfNeeded() {
        let key = updateKey
        let mark = "mulmo-control.skidded-update-key"
        guard !key.isEmpty, UserDefaults.standard.string(forKey: mark) != key else { return }
        UserDefaults.standard.set(key, forKey: mark)
        skidOffset = SKID_FROM
        skidAngle = SKID_TILT
        // 初期値を置いた同じ回で animation を掛けると、いまの位置から
        // 画面外へ飛んでから戻る動きになる。1回ぶん待ってから掛ける。
        DispatchQueue.main.async { runSkid() }
    }

    private func runSkid() {
        withAnimation(.timingCurve(0, 0.7, 0.6, 1, duration: 0.55)) {
            skidOffset = 0
            skidAngle = SKID_TILT - 2
        }
        // spring の行き過ぎと揺り戻しが、CSS の 55% / 85% のキーフレームに当たる。
        withAnimation(.spring(response: 0.55, dampingFraction: 0.45).delay(0.5)) {
            skidAngle = 0
        }
    }
}

/// 滑り込みの強さ。ここだけ触れば効き具合を変えられる。
///
/// 傾きは CSS の -14deg から浅くしてある。パネルは幅 370 で、下端を軸に
/// 14度ねじると右上が 90pt ほど持ち上がり、パネルからはみ出して切れる。
private let SKID_FROM: CGFloat = 240
private let SKID_TILT: Double = -7

/// ログインが切れている間だけ、運用タブの一番上に出る。
/// 更新のバナーと違って、押さないと MulmoClaude のチャットが直らない。
struct ClaudeLoginCard: View {
    @ObservedObject var model: ControlModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Palette.warn)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude のログインが切れています")
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                Text("MulmoClaude のチャットが使えません")
                    .font(AppFont.small)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button("ログインし直す", action: model.openClaudeLogin)
                .buttonStyle(.plain)
                .font(AppFont.action)
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Palette.accent, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 本文をそのまま出しつつ、「ガイド: https://…」の行だけは押せるリンクにする。
/// 詳しい説明は上流のガイドやリリースノートにあるので、1クリックで行けた方がいい。
struct LinkedText: View {
    let text: String

    /// リンクの文言は、その行が自分で名乗っているもの（`ガイド:` `詳しく:`）を使う。
    /// 以前はどの行でも「新機能を見る」と出していたが、飛び先には直った不具合も
    /// 並ぶので、機能だけがあるように読めていた（Issue #89）。
    private func label(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: CharacterSet(charactersIn: " :："))
        return trimmed.isEmpty ? "開く" : trimmed
    }

    private var blocks: [(body: String, url: URL?)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let raw = String(line)
            guard let range = raw.range(of: "https://"),
                  let url = URL(string: String(raw[range.lowerBound...]).trimmingCharacters(in: .whitespaces))
            else { return (raw, nil) }
            return (String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces), url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if let url = block.url {
                    Link(label(block.body), destination: url)
                        .font(AppFont.small)
                        .foregroundStyle(Palette.accentText)
                } else if !block.body.isEmpty {
                    Text(block.body)
                        .font(AppFont.small)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct NoticeCard: View {
    let notice: NoticeMessage
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(AppFont.body)
                .foregroundStyle(Palette.secondaryText)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                LinkedText(text: notice.text)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold, design: .default))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// MulmoClaude のパネル1行目（Issue #170）。
///
/// 「動作中・ブラウザで使えます」だけでは、**いまどちらのモードで動いて
/// いるか**が分からない。作業中に画面が勝手にリロードされるかどうかがそこで
/// 決まっているので、押さずに見える場所はここしかない。
@MainActor func mulmoClaudeSubtitle(_ model: ControlModel) -> String {
    guard model.mcInstalled else { return "未インストール" }
    if model.mcRunning { return "動作中・\(model.mcMode.label)（\(model.mcMode.note)）" }
    return "停止中・次は\(model.mcMode.label)で起動します"
}

struct OperateView: View {
    @ObservedObject var model: ControlModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ServicePanel(
                title: "MulmoTerminal",
                subtitle: model.mtInstalled ? (model.mtRunning ? "動作中・ブラウザで使えます" : "停止中") : "未インストール",
                isRunning: model.mtRunning,
                isAvailable: model.mtInstalled,
                accent: Palette.accent,
                inactiveTitle: model.mtInstalled ? "起動" : "インストール",
                inactiveSystemImage: model.mtInstalled ? "play.fill" : "arrow.down.circle",
                openAction: model.openMT,
                startAction: model.mtInstalled ? model.startMT : model.installMT,
                stopAction: model.stopMT,
                restartAction: model.restartMT
            ) {
                LogDisclosure(action: model.openLogs)
            }
            ServicePanel(
                title: "MulmoClaude",
                subtitle: mulmoClaudeSubtitle(model),
                isRunning: model.mcRunning,
                isAvailable: model.mcInstalled,
                accent: Palette.accent,
                inactiveTitle: model.mcInstalled ? "起動" : "入手",
                inactiveSystemImage: model.mcInstalled ? "play.fill" : "arrow.up.right",
                openAction: model.openMC,
                startAction: model.mcInstalled ? model.startMC : model.openMCRepo,
                stopAction: model.stopMC,
                restartAction: model.restartMC,
                trailingControl: { model.mcInstalled ? AnyView(ModeButton(model: model)) : AnyView(EmptyView()) }
            ) {
                if model.mcInstalled {
                    LogDisclosure(action: model.openMCLogs)
                } else {
                    Button("入手", action: model.openMCRepo)
                }
            }
            GuideToggleRow()
            InstalledFamilyPanel(model: model)
        }
    }
}

struct InstalledFamilyPanel: View {
    @ObservedObject var model: ControlModel

    private var installedPackages: [FamilyPackage] {
        familyPackages.filter { model.familyInstalled[$0.id] ?? false }
    }

    var body: some View {
        if !installedPackages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Color.clear
                        .frame(width: 10, height: 10)
                    Text("追加ツール")
                        .font(AppFont.section)
                        .foregroundStyle(Palette.primaryText)
                    Spacer()
                }
                VStack(spacing: 9) {
                    ForEach(installedPackages) { package in
                        FamilyToolRow(
                            package: package,
                            update: model.updateItems.first(where: { $0.id == package.id || $0.name == package.packageName || $0.name == package.title })
                        )
                    }
                }
            }
            .padding(14)
            .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct FamilyToolRow: View {
    let package: FamilyPackage
    let update: MulmoUpdateItem?
    @State private var showsDetail = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Palette.ok)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(package.title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                Text(detailText)
                    .font(AppFont.small)
                    .foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Palette.secondaryText)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showsDetail.toggle()
        }
        .popover(isPresented: $showsDetail, arrowEdge: .trailing) {
            FamilyToolDetail(package: package, detailText: detailText)
                .frame(width: 250)
        }
    }

    private func updateDetail(_ item: MulmoUpdateItem) -> String {
        versionDetail(status: item.status, current: item.current, latest: item.latest,
                      fallback: "導入済み")
    }

    private var detailText: String {
        "\(package.note) ・ \(update.map(updateDetail) ?? "導入済み")"
    }
}

struct FamilyToolDetail: View {
    let package: FamilyPackage
    let detailText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.ok)
                    .frame(width: 8, height: 8)
                Text(package.title)
                    .font(AppFont.section)
                    .foregroundStyle(Palette.primaryText)
            }
            Hairline()
            DetailBlock(title: "できること", text: package.capability)
            DetailBlock(title: "使う場所", text: package.useWhere)
        }
        .padding(14)
    }
}

struct LogDisclosure: View {
    let action: () -> Void
    @State private var showsDetail = false

    var body: some View {
        HStack(spacing: 4) {
            Text("ログ")
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold, design: .default))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showsDetail.toggle()
        }
        .popover(isPresented: $showsDetail, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ログ")
                    .font(AppFont.section)
                    .foregroundStyle(Palette.primaryText)
                Text("出力ログのフォルダを開きます。")
                    .font(AppFont.small)
                    .foregroundStyle(Palette.secondaryText)
                Button("ログフォルダを開く", action: action)
                    .buttonStyle(.plain)
                    .font(AppFont.action)
                    .foregroundStyle(Palette.accentText)
            }
            .padding(14)
            .frame(width: 190)
        }
    }
}

/// MulmoClaude をどちらのモードで起こすかの切り替え（Issue #168 / #170）。
///
/// 最初はログと同じ「小さいテキストの行」にしたが、**入れた本人以外は
/// 見つけられなかった。** 状態の表示も兼ねていたので、押せる物に読めない。
/// ログは押さなくても困らないもの、モードは押さなくても分かる必要がある
/// もので、性質が違う。状態は panel の1行目へ移し、切り替えは開く / 再起動 /
/// 停止と同じボタンの列に置く。
struct ModeButton: View {
    @ObservedObject var model: ControlModel
    @State private var showsDetail = false

    var body: some View {
        CapsuleButton(title: "モード", systemImage: "arrow.left.arrow.right", style: .quiet) {
            showsDetail.toggle()
        }
        .popover(isPresented: $showsDetail, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("起動のしかた")
                    .font(AppFont.section)
                    .foregroundStyle(Palette.primaryText)
                ForEach([MulmoClaudeMode.app, MulmoClaudeMode.dev], id: \.self) { mode in
                    Button {
                        model.setMCMode(mode)
                        showsDetail = false
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: mode == model.mcMode ? "largecircle.fill.circle" : "circle")
                                Text(mode.label)
                                    .font(AppFont.action)
                            }
                            .foregroundStyle(Palette.primaryText)
                            Text(mode.detail)
                                .font(AppFont.small)
                                .foregroundStyle(Palette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("切り替えると、動いている MulmoClaude は起こし直します。開くアドレスも変わります。")
                    .font(AppFont.small)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260)
        }
    }
}

struct DetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.rowTitle)
                .foregroundStyle(Palette.primaryText)
            Text(text)
                .font(AppFont.small)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EnvironmentView: View {
    @ObservedObject var model: ControlModel

    var body: some View {
        SetupPanel(model: model)
    }
}

struct SetupPanel: View {
    @ObservedObject var model: ControlModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("環境")
                .font(AppFont.section)
                .foregroundStyle(Palette.primaryText)

            VStack(spacing: 7) {
                SetupRow(
                    title: "MulmoTerminal",
                    detail: model.mtInstalled ? "インストール済み" : "未インストール",
                    ok: model.mtInstalled,
                    buttonTitle: model.mtInstalled ? nil : "インストール",
                    action: model.installMT
                )
                if model.mcInstalled {
                    SetupRow(title: "MulmoClaude", detail: "インストール済み", ok: true)
                    SetupRow(
                        title: "Claude のログイン",
                        detail: model.claudeLogin.detail,
                        ok: !model.claudeLogin.isExpired,
                        buttonTitle: model.claudeLogin.isExpired ? "ログインし直す" : nil,
                        action: model.openClaudeLogin
                    )
                } else {
                    SetupRow(
                        title: "MulmoClaude",
                        detail: "未インストール",
                        ok: false,
                        buttonTitle: "入手",
                        action: model.openMCRepo
                    )
                }
                SetupRow(
                    title: "Mulmo Control を自動で起動",
                    detail: model.launchAtLogin ? "オン" : "オフ",
                    ok: model.launchAtLogin,
                    buttonTitle: model.launchAtLogin ? "やめる" : "オンにする",
                    action: model.toggleLaunchAtLogin
                )
            }
            Hairline()
                .padding(.vertical, 2)
            // スマホ連携は4つある。以前は行の名前を「スマホ連携（MulmoTerminal）」
            // のように書いていたが、幅に入らず「スマホ連携（Mulmo…」と潰れて、
            // どれがどれだか読めなかった（Issue #156 と同じ形）。主語は見出しに
            // 出して、行は名前だけにする。
            Text("スマホ連携")
                .font(AppFont.section)
                .foregroundStyle(Palette.primaryText)
            VStack(spacing: 7) {
                if model.mcInstalled {
                    SetupRow(
                        title: "MulmoTerminal",
                        detail: model.remoteHost.detail,
                        ok: model.remoteHost.state == "online",
                        buttonTitle: remoteHostButtonTitle(model.remoteHost),
                        action: model.remoteHost.isOffline || model.remoteHost.canConnectFromControl
                            ? model.reconnectRemoteHost
                            : model.openMT
                    )
                    SetupRow(
                        title: "MulmoClaude",
                        detail: model.mcRemoteHost.detail,
                        ok: model.mcRemoteHost.state == "online",
                        buttonTitle: remoteHostButtonTitle(model.mcRemoteHost),
                        action: model.mcRemoteHost.isOffline || model.mcRemoteHost.canConnectFromControl
                            ? model.reconnectMCRemoteHost
                            : model.openMC
                    )
                }
                SetupRow(
                    title: "Claude Code",
                    detail: model.claudeRemote.detail,
                    ok: agentRemoteOK(model.claudeRemote),
                    buttonTitle: agentRemoteButtonTitle(model.claudeRemote),
                    action: agentRemoteOK(model.claudeRemote)
                        ? model.openClaudeRemote
                        : model.startClaudeRemote,
                    extraTitle: agentRemoteCanStop(model.claudeRemote) ? "止める" : nil,
                    extraAction: model.stopClaudeRemote
                )
                SetupRow(
                    title: "Codex",
                    detail: model.codexRemote.detail,
                    ok: agentRemoteOK(model.codexRemote),
                    buttonTitle: codexButtonTitle(model.codexRemote),
                    action: model.codexRemote.state == "online"
                        ? model.pairCodexRemote
                        : model.startCodexRemote,
                    extraTitle: agentRemoteCanStop(model.codexRemote) ? "止める" : nil,
                    extraAction: model.stopCodexRemote
                )
                if !model.codexRemote.code.isEmpty {
                    Text("スマホに入れるコード: \(model.codexRemote.code)")
                        .font(AppFont.small)
                        .foregroundStyle(Palette.accentText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Hairline()
                .padding(.vertical, 2)
            Text("最新版")
                .font(AppFont.section)
                .foregroundStyle(Palette.primaryText)
            VStack(spacing: 7) {
                SetupRow(title: "Mulmo Control", detail: mulmoControlDetail(model.selfUpdate), ok: model.selfUpdate.status == "current")
                ForEach(model.updateItems.filter { $0.id == "mulmoterminal" || $0.id == "mulmoclaude" }) { item in
                    UpdateRow(item: item)
                }
                if model.updateItems.isEmpty {
                    SetupRow(title: "Mulmo", detail: "未確認", ok: false)
                }
            }
            Hairline()
                .padding(.vertical, 2)
            Text("前回の更新")
                .font(AppFont.section)
                .foregroundStyle(Palette.primaryText)
            LinkedText(text: model.lastUpdateReport)
            if let note = lastUpdateNote {
                Text(note)
                    .font(AppFont.small)
                    .foregroundStyle(Palette.ok)
            }
        }
        .padding(13)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 「前回の更新」に残った失敗が、その後どうなったかを添える（Issue #136）。
    ///
    /// この記録は更新した瞬間に書かれ、次の更新まで書き換わらない。あとから別の
    /// 経路で最新になっても失敗の記録だけが残り、同じ画面の上半分が「すべて最新」
    /// なのに下半分が失敗を訴える、という矛盾になる。実際に起きた（#129 を直した
    /// あとの化石が「MulmoCast: 2.9.2 のまま」と言い続けていた）。
    ///
    /// 記録は消さない。当時動かなかったこと自体は事実で、理由を残すと決めた場所
    /// でもある（#104）。いまどうなっているかを1行足すだけにする。
    private var lastUpdateNote: String? {
        guard model.lastUpdateReport.contains("更新されなかったもの") else { return nil }
        guard model.selfUpdate.status != "update",
              model.updateItems.allSatisfy({ $0.status != "update" }) else { return nil }
        return "その後、すべて最新になっています"
    }

    /// 「最新 1.0.45」「1.0.45 → 1.0.46」のように、いま動いている版と更新の有無を
    /// 並べて出す（Issue #10）。版は Bundle.main から読むので、記録ではなく実物を
    /// 見ている。同じ欄に並ぶ MulmoTerminal / MulmoClaude と書き方を揃えてある。
    private func mulmoControlDetail(_ status: SelfUpdateStatus) -> String {
        versionDetail(
            status: status.status, current: appVersion, latest: status.latestVersion,
            fallback: selfUpdateFallback(status)
        )
    }

    /// 最新でも更新中でもないときだけ使う。理由が書いてあればそれを、
    /// 無ければ他の行と同じ「未確認 1.0.45」の形にする。
    private func selfUpdateFallback(_ status: SelfUpdateStatus) -> String {
        if status.status != "unknown", !status.detail.isEmpty { return status.detail }
        return appVersion.isEmpty ? "未確認" : "未確認 \(appVersion)"
    }
}

struct FamilyView: View {
    @ObservedObject var model: ControlModel
    let installAction: (FamilyPackage) -> Void

    private var uninstalledPackages: [FamilyPackage] {
        familyPackages.filter { !(model.familyInstalled[$0.id] ?? false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("追加インストール")
                    .font(AppFont.section)
                    .foregroundStyle(Palette.primaryText)
                Text(model.updateSummary)
                    .font(AppFont.body)
                    .foregroundStyle(Palette.secondaryText)
            }

            VStack(spacing: 10) {
                ForEach(uninstalledPackages) { package in
                    FamilyPackageRow(
                        package: package,
                        update: model.updateItems.first(where: { $0.id == package.id || $0.name == package.packageName || $0.name == package.title }),
                        installAction: { installAction(package) }
                    )
                }
                if uninstalledPackages.isEmpty {
                    Text("追加できるものはありません")
                        .font(AppFont.body)
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            }
        }
        .padding(13)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct FamilyPackageRow: View {
    let package: FamilyPackage
    let update: MulmoUpdateItem?
    let installAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.warn)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.title)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Palette.primaryText)
                    Text(package.note)
                        .font(AppFont.small)
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                if package.isInstallable {
                    Button("インストール", action: installAction)
                        .buttonStyle(.plain)
                        .font(AppFont.action)
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.controlFill, in: Capsule())
                } else {
                    Text("準備中")
                        .font(AppFont.action)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.controlFill, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Text(package.isInstallable ? "未導入" : "未公開")
                if package.isInstallable, let update {
                    Text(updateDetail(update))
                }
            }
            .font(AppFont.small)
            .foregroundStyle(Palette.secondaryText)
            .padding(.leading, 15)
        }
    }

    private func updateDetail(_ item: MulmoUpdateItem) -> String {
        versionDetail(status: item.status, current: item.current, latest: item.latest,
                      fallback: "最新版未確認")
    }
}

/// 版と更新の有無を、ひとつの書き方に揃える。「最新 4.10.0」「4.9.0 → 4.10.0」。
/// 以前は同じ欄に「1.0.45 ・ 最新」と「最新 4.10.0」が並んでいた。整形を各所に
/// 書くとまた割れるので、増やすときはここに足す。
func versionDetail(status: String, current: String, latest: String, fallback: String) -> String {
    switch status {
    case "current":
        return current.isEmpty ? "最新" : "最新 \(current)"
    case "update":
        return current.isEmpty || latest.isEmpty ? "更新あり" : "\(current) → \(latest)"
    default:
        return fallback
    }
}

struct SetupRow: View {
    let title: String
    let detail: String
    let ok: Bool
    var buttonTitle: String?
    var action: (() -> Void)?
    /// 押す所が2つ要る行のため（Issue #160）。エージェントの連携は「開く」と
    /// 「止める」が同時に要る。渡さなければ今まで通り1つだけ出る。
    var extraTitle: String?
    var extraAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Palette.ok : Palette.warn)
                .frame(width: 7, height: 7)
            Text(title)
                .font(AppFont.rowTitle)
                .foregroundStyle(Palette.primaryText)
            Spacer()
            Text(detail)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(AppFont.small)
                .foregroundStyle(Palette.secondaryText)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.plain)
                    .font(AppFont.small)
                    .foregroundStyle(Palette.accentText)
            }
            if let extraTitle, let extraAction {
                Button(extraTitle, action: extraAction)
                    .buttonStyle(.plain)
                    .font(AppFont.small)
                    .foregroundStyle(Palette.accentText)
            }
        }
    }
}

struct UpdateRow: View {
    let item: MulmoUpdateItem

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(item.displayName)
                .font(AppFont.rowTitle)
                .foregroundStyle(Palette.primaryText)
            Spacer()
            Text(detail)
                .font(AppFont.small)
                .foregroundStyle(Palette.secondaryText)
        }
    }

    private var color: Color {
        switch item.status {
        case "current":
            return Palette.ok
        case "update":
            return Palette.warn
        default:
            return Color.secondary.opacity(0.55)
        }
    }

    private var detail: String {
        if item.status == "missing" { return "未導入" }
        return versionDetail(
            status: item.status, current: item.current, latest: item.latest,
            fallback: item.current.isEmpty ? "未確認" : "未確認 \(item.current)"
        )
    }
}

struct ServicePanel<Extra: View>: View {
    let title: String
    let subtitle: String
    let isRunning: Bool
    let isAvailable: Bool
    let accent: Color
    var inactiveTitle = "起動"
    var inactiveSystemImage = "play.fill"
    let openAction: () -> Void
    let startAction: () -> Void
    let stopAction: () -> Void
    let restartAction: () -> Void
    /// 動いているときのボタン列に足すもの（Issue #170）。押して選ぶものは、
    /// 下のテキストの行ではなくここに置く。あちらはログ用で、押さなくても
    /// 困らないものの置き場所。
    var trailingControl: () -> AnyView = { AnyView(EmptyView()) }
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    // 下敷きではなく「印」なので accentText 側。accent は白い文字を
                    // 乗せるために暗く抑えてあり、暗い台紙の上では 2.7:1 まで落ちて
                    // 図形の基準（3:1）を割る。明るいときは両者が同じ値なので、
                    // ライトモードの見た目は変わらない。
                    .fill(isRunning ? Palette.accentText : Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFont.cardTitle)
                        .foregroundStyle(Palette.primaryText)
                    Text(subtitle)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer()
            }
            if isAvailable {
                HStack(spacing: 8) {
                    CapsuleButton(title: "開く", systemImage: "arrow.up.right", style: .primary(accent), action: openAction)
                    if isRunning {
                        CapsuleButton(title: "再起動", systemImage: "arrow.clockwise", style: .quiet, action: restartAction)
                        Button("停止") {
                            stopAction()
                        }
                        .buttonStyle(.plain)
                        .font(AppFont.action)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Palette.controlFill, in: Capsule())
                        trailingControl()
                    } else {
                        // 停止中に出るボタンが「開く」だけで、起動できるとは読めなかった
                        // （#139）。`startAction` はこの枝が空だったせいで未インストール
                        // のときにしか描かれず、インストール済みなら到達できなかった。
                        // `openAction` も止まっていれば起動してから開くが、それが分かるのは
                        // 押したあとで、画面を見て分かる必要がある。
                        CapsuleButton(title: inactiveTitle, systemImage: inactiveSystemImage, style: .quiet, action: startAction)
                        trailingControl()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    CapsuleButton(title: inactiveTitle, systemImage: inactiveSystemImage, style: .primary(accent), action: startAction)
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                extra()
            }
            .buttonStyle(.borderless)
            .font(AppFont.small)
            .foregroundStyle(Palette.secondaryText)
        }
        .padding(14)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 明るいときと暗いときで、違う色を返す（#143）。
///
/// 台紙は `.ultraThinMaterial` で、これは OS の外観にひとりでについていく。
/// 色のほうが決め打ちだったので、夜になると台紙だけが暗くなり、文字と罫線は
/// 明るいとき用の濃さのまま残っていた。補助的な文字から順に沈んで、利用者の
/// 写真では「最新版」の版番号が完全に消えていた。
///
/// 作者の Mac がライトモードなら、この状態は一度も画面に出ない。#6 と同じ穴。
///
/// SwiftUI の `Color` は自分で外観を見られないので、`NSColor` の
/// dynamicProvider に預ける。描画のたびに、そのビューの外観で評価される。
/// 静的に1回決めてしまう書き方（`Color(NSApp.effectiveAppearance ...)` など）だと、
/// 起動後に夜になった人には切り替わらない。
private func adaptive(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    })
}

/// `Color(red:green:blue:)` は sRGB。NSColor 側も sRGB で揃える。
/// `NSColor(red:...)` は calibrated RGB なので、同じ数値でも色がずれる。
private func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

enum Palette {
    // light: の値は従来のまま。ライトモードの見た目は変えない。
    static let primaryText = adaptive(light: srgb(0.12, 0.12, 0.14), dark: srgb(0.93, 0.93, 0.96))
    static let secondaryText = adaptive(light: srgb(0.43, 0.44, 0.48), dark: srgb(0.69, 0.70, 0.75))
    // 暗いときは、白を重ねて浮かせる。明るいときと同じ 30% だと白すぎる。
    static let panelFill = adaptive(light: srgb(1, 1, 1, 0.30), dark: srgb(1, 1, 1, 0.07))
    static let controlFill = adaptive(light: srgb(0.47, 0.47, 0.50, 0.16), dark: srgb(1, 1, 1, 0.14))
    static let hairline = adaptive(light: srgb(0, 0, 0, 0.13), dark: srgb(1, 1, 1, 0.16))
    // accent は下敷き用。選択中のタブ、主ボタン、動作中のドットに使う。白い文字を
    // 乗せるので、明るくしすぎるとその白が浮く。
    //
    // 文字色は accentText に分けた。1色で兼ねることはできない。暗い台紙の上で
    // 文字として 4.5:1 を出すには輝度 0.41 以上が要る一方、白い文字の下敷きとして
    // 4.5:1 を保つには 0.18 以下でなければならない。両立しない範囲なので、明るい
    // ときは同じ色、暗いときだけ分かれる。
    static let accent = adaptive(light: srgb(0.00, 0.48, 0.78), dark: srgb(0.10, 0.53, 0.85))
    static let accentText = adaptive(light: srgb(0.00, 0.48, 0.78), dark: srgb(0.45, 0.75, 1.00))
    static let ok = adaptive(light: srgb(0.20, 0.76, 0.36), dark: srgb(0.32, 0.85, 0.47))
    static let warn = adaptive(light: srgb(0.90, 0.58, 0.18), dark: srgb(0.98, 0.72, 0.30))
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
    }
}

enum CapsuleButtonStyle {
    case primary(Color)
    case quiet
}

struct CapsuleButton: View {
    let title: String
    let systemImage: String
    let style: CapsuleButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold, design: .default))
            }
            .font(AppFont.action)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary:
            return .white
        case .quiet:
            return Palette.primaryText
        }
    }

    private var background: Color {
        switch style {
        case .primary(let color):
            return color
        case .quiet:
            return Palette.controlFill
        }
    }
}

struct FooterButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        // 余白と背景は必ず label の中に置く。外側に付けると、見えているカプセルより
        // 当たり判定が狭くなり（文字とアイコンの上だけ）、縁を押しても反応しない
        // （Issue #34）。contentShape で形も明示しておく。
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(AppFont.action)
            .foregroundStyle(role == .destructive ? Color.red.opacity(0.85) : Palette.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Palette.controlFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 127.0.0.1 の指定ポートで誰かが待ち受けているか。
///
/// 以前は `lsof` を起動していたが、全プロセスのファイルディスクリプタを走査する
/// ので1回およそ 35ms かかっていた。これを5秒ごとに2〜3回やっていたのが、
/// 「エネルギーを著しく消費中」の主因のひとつ（Issue #38）。
/// ループバックへ繋いでみるだけなら桁違いに安く、プロセスも起動しない。
///
/// 繋がった接続はすぐ閉じる。待ち受け側から見ると、何も送らずに切れた接続が
/// 1本増えるだけで、HTTP サーバーはこれを無視する。
/// 5173 に居るのが本当に MulmoClaude かどうかを、返ってくる中身で確かめる（Issue #93）。
///
/// ポートが開いているかどうかだけでは足りない。5173 は Vite の既定ポートなので、
/// 他のプロジェクトを開いているだけで「動作中・ブラウザで使えます」と出て、
/// `開く` が他人のアプリを表示していた。
///
/// プロセス表を見る手もあるが、実測で `lsof` は1周 210 ms かかる（ポート確認は
/// 0.1 ms、この HTTP は 1.0 ms）。ポーリングのたびに払える額ではない。
///
/// 印は2つあり、どちらか一方でも出れば本物とみなす。片方が上流の都合で
/// 変わっても、黙って「停止中」になり続けることがないようにするため。
func servesMulmoClaude(port: Int) -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return false }
    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    request.cachePolicy = .reloadIgnoringLocalCacheData

    var body = ""
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data, let text = String(data: data, encoding: .utf8) { body = text }
        done.signal()
    }.resume()
    guard done.wait(timeout: .now() + 3) == .success else { return false }

    return body.contains("<title>MulmoClaude</title>") || body.contains("gui-chat-protocol")
}

func portIsOpen(_ port: Int) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = UInt16(port).bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    let connected = withUnsafePointer(to: &addr) { raw in
        raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return connected == 0
}

func commandPath(_ name: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", "command -v \(name)"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    } catch {
        return nil
    }
}

func readUpdateText() -> String {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: updatePath)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return "更新: 未確認"
    }
    let current = json["current"] as? String ?? "?"
    let latest = json["latest"] as? String ?? "?"
    let status = json["status"] as? String ?? "unknown"
    if status == "update" { return "更新あり: \(current) → \(latest)" }
    if status == "current" { return "最新版: \(current)" }
    return "更新確認できません: \(current)"
}

func readMulmoUpdates() -> MulmoUpdates {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: mulmoUpdatesPath)),
          let updates = try? JSONDecoder().decode(MulmoUpdates.self, from: data) else {
        return MulmoUpdates(checkedAt: "", summary: "更新: 未確認", items: [])
    }
    let visibleItems = updates.items.filter { item in
        item.id != "create-plugin"
    }
    let summary: String
    if visibleItems.contains(where: { $0.status == "update" }) {
        summary = "更新あり"
    } else if visibleItems.isEmpty {
        summary = "未確認"
    } else if visibleItems.contains(where: { $0.status != "current" && $0.status != "missing" }) {
        summary = "一部未確認"
    } else {
        summary = "最新"
    }
    return MulmoUpdates(checkedAt: updates.checkedAt, summary: "更新: \(summary)", items: visibleItems)
}

func readLastUpdateReport() -> String {
    guard let value = try? String(contentsOfFile: lastUpdateReportPath, encoding: .utf8) else {
        return "まだありません"
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "まだありません" : trimmed
}

func readRemoteHostStatus(_ path: String = remoteHostPath) -> RemoteHostStatus {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let status = try? JSONDecoder().decode(RemoteHostStatus.self, from: data) else {
        return RemoteHostStatus(checkedAt: "", state: "unknown", hasSession: false, detail: "未確認", hasStash: nil)
    }
    return status
}

/// 登録したプロジェクトの一覧と、その稼働状態（Issue #152）。
/// エージェントのスマホ連携の状態を読む（Issue #160）。
///
/// 書き置きが無い・壊れているときは「未確認」に落とす。作り話をしない。
func readAgentRemote(_ path: String) -> AgentRemote {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let status = try? JSONDecoder().decode(AgentRemote.self, from: data) else {
        return AgentRemote(state: "unknown", detail: "未確認", url: nil, pairCode: nil)
    }
    return status
}

func readClaudeLoginStatus() -> ClaudeLoginStatus {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeLoginPath)),
          let status = try? JSONDecoder().decode(ClaudeLoginStatus.self, from: data) else {
        return ClaudeLoginStatus(checkedAt: "", state: "unknown", detail: "未確認")
    }
    return status
}

func readSelfUpdateStatus() -> SelfUpdateStatus {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: selfUpdatePath)),
          let status = try? JSONDecoder().decode(SelfUpdateStatus.self, from: data) else {
        return SelfUpdateStatus(status: "unknown", detail: "未確認")
    }
    return status
}

func readLastUpdateSummary() -> String {
    guard let value = try? String(contentsOfFile: lastUpdateSummaryPath, encoding: .utf8) else {
        return ""
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}
