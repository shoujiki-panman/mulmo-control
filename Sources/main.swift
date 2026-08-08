import SwiftUI
import AppKit
import UserNotifications

private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
private let localBin = "\(homeDir)/.local/bin"
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
private func tool(_ name: String) -> String { "\"\(toolsDir)/\(name)\"" }
private func bin(_ name: String) -> String { "\"\(localBin)/\(name)\"" }
private let updatePath = "\(homeDir)/Documents/Codex/SwiftBarLogs/mulmoterminal-update.json"
private let mulmoUpdatesPath = "\(homeDir)/Documents/Codex/SwiftBarLogs/mulmo-updates.json"
private let selfUpdatePath = "\(homeDir)/Documents/Codex/SwiftBarLogs/mulmo-control-self-update.json"
private let claudeLoginPath = "\(homeDir)/Documents/Codex/SwiftBarLogs/claude-login.json"
private let remoteHostPath = "\(homeDir)/Documents/Codex/SwiftBarLogs/remote-host.json"
private let lastUpdateReportPath = "\(homeDir)/Documents/Codex/SwiftBarLogs/mulmo-control-last-update.txt"
private let lastUpdateSummaryPath = "\(homeDir)/Documents/Codex/SwiftBarLogs/mulmo-control-last-update-summary.txt"
// install.sh が書き出す app-info.env から MulmoClaude の場所を読む
private func configuredMulmoClaudeDir() -> String {
    let fallback = "\(homeDir)/mulmoclaude"
    let configPath = "\(homeDir)/Library/Application Support/Mulmo Control/app-info.env"
    guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else { return fallback }
    let key = "MULMO_CONTROL_MULMOCLAUDE_DIR="
    for line in text.split(separator: "\n") {
        guard line.hasPrefix(key) else { continue }
        let value = line.dropFirst(key.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        if !value.isEmpty { return value }
    }
    return fallback
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

/// スマホ連携（RemoteHost）の状態。切れても MulmoTerminal は動き続けるので、
/// 放っておくと気づけない。never = 一度も繋いでいない（再接続する先が無い）。
struct RemoteHostStatus: Decodable {
    let checkedAt: String
    let state: String   // online / offline / never / unknown
    let hasSession: Bool
    let detail: String

    var isOffline: Bool { state == "offline" }
    var neverConnected: Bool { state == "never" }
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
    let checkedAt: String
    let status: String
    let installedCommit: String
    let latestCommit: String
    let detail: String
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
    @Published var reviveEnabled = false
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
    @Published var familyInstalled: [String: Bool] = [:]
    @Published var actionText: String?
    @Published var notice: NoticeMessage?
    @Published var lastUpdateReport = readLastUpdateReport()

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
        if open { refresh() }
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

    var menuTitle: String {
        hasAnyUpdates ? "Mulmo 更新あり" : "\(mtRunning ? "MT on" : "MT off") / \(mcRunning ? "MC on" : "MC off")"
    }

    var titleColor: Color {
        if hasAnyUpdates {
            return Palette.warn
        }
        return (mtRunning || mcRunning) ? Color.green : Color.red
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

    func refresh() {
        // ポート確認とファイル読みだけ。メニューバーのアイコンはこれで足りるので、
        // 閉じている間はここまでで済ませる（Issue #38）。
        mtRunning = portIsOpen(34567)
        mcRunning = portIsOpen(5173) || portIsOpen(3001)
        reviveEnabled = FileManager.default.fileExists(atPath: "\(homeDir)/.mulmoterminal/keepalive-enabled")
        mtInstalled = FileManager.default.isExecutableFile(atPath: "\(localBin)/mulmoterminal")
        mcInstalled = FileManager.default.fileExists(atPath: mulmoClaudeDir)
        updateText = readUpdateText()
        let updates = readMulmoUpdates()
        updateSummary = updates.summary
        updateItems = updates.items
        selfUpdate = readSelfUpdateStatus()
        claudeLogin = readClaudeLoginStatus()
        remoteHost = readRemoteHostStatus()
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
            openURL("http://localhost:34567")
        } else {
            runThenOpen(bin("mulmoterminal-start"), url: "http://localhost:34567")
        }
    }

    func openMC() {
        guard mcInstalled else {
            showMessage(title: "MulmoClaudeが未インストールです", text: "先にインストールしてください。")
            return
        }
        if mcRunning {
            openURL("http://localhost:5173")
        } else {
            runThenOpen(tool("mulmoclaude-start"), url: "http://localhost:5173")
        }
    }
    func startMT() { run(bin("mulmoterminal-start")) }
    func stopMT() { run(bin("mulmoterminal-stop")) }
    func restartMT() { run(bin("mulmoterminal-restart")) }
    func checkUpdate() { run(tool("mulmoterminal-check-update"), label: "更新を確認中") }
    func checkAllUpdates() {
        run("""
        \(tool("mulmo-check-updates"))
        \(tool("mulmo-control-self-update")) check
        \(tool("mulmo-check-claude-login"))
        \(tool("mulmo-check-remote-host"))
        """, label: "更新を確認中")
    }

    /// 切れたスマホ連携を繋ぎ直す。初回接続はブラウザでの Google サインインが
    /// 要る（idToken が作れない）ので、そちらは画面への案内に留める。
    func reconnectRemoteHost() {
        run(tool("mulmo-remote-host-reconnect"), label: "スマホ連携を繋ぎ直しています")
    }

    /// ログインし直す入口まで連れて行く。/login の入力とブラウザでの
    /// サインインは本人がやる（OAuth なのでアプリが代われない）。
    func openClaudeLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(mulmoClaudeDir) && claude"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if error != nil {
            showMessage(
                title: "ターミナルを開けませんでした",
                text: "ターミナルで次を実行してください:\ncd \(mulmoClaudeDir) && claude\nそのあと /login と入力します。"
            )
            return
        }
        showMessage(
            title: "ターミナルを開きました",
            text: "信頼を聞かれたら承認し、/login と入力してください。ブラウザでサインインすると復旧します。"
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
        let prefix = "\(homeDir)/.local/share/mulmo-family"
        let binPath = "\(prefix)/node_modules/.bin/\(package.commandName)"
        run("""
        mkdir -p "\(prefix)" "\(localBin)" /private/tmp/npm-cache-mulmo-control
        NPM_CONFIG_CACHE="/private/tmp/npm-cache-mulmo-control" "\(npmPath)" install --prefix "\(prefix)" "\(package.packageName)@latest"
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

    func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(homeDir)/.mulmoterminal/logs"))
    }

    func openMCLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(homeDir)/Documents/Codex/SwiftBarLogs"))
    }

    func openActionLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/mulmo-control-action.log"))
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
        let prefix = "\(homeDir)/.local/share/mulmo-family"
        let installLines = packages.map { package in
            let binPath = "\(prefix)/node_modules/.bin/\(package.commandName)"
            return """
            NPM_CONFIG_CACHE="/private/tmp/npm-cache-mulmo-control" "\(npmPath)" install --prefix "\(prefix)" "\(package.packageName)@latest"
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

    private func run(_ command: String, label: String? = nil) {
        actionText = label
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "(\n\(command)\n) >/tmp/mulmo-control-action.log 2>&1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "failed: \(error)\n".write(toFile: "/tmp/mulmo-control-action.log", atomically: true, encoding: .utf8)
            }
            let succeeded = process.terminationStatus == 0
            await MainActor.run {
                self.refreshAfterAction()
                // 終了コードが非0でも報告は出す。一部だけ失敗したときに黙って
                // 消すと、上がった物まで無かったことになる。何が動いて何が
                // 動かなかったかは、更新後の実測値が知っている。
                self.recordPendingUpdateReport()
                self.actionText = succeeded ? nil : "失敗しました。ログを確認してください"
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
                """
            ]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "silent update check failed: \(error)\n".write(toFile: "/tmp/mulmo-control-action.log", atomically: true, encoding: .utf8)
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
            process.arguments = ["-lc", "(\n\(command)\n) >/tmp/mulmo-control-action.log 2>&1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "failed: \(error)\n".write(toFile: "/tmp/mulmo-control-action.log", atomically: true, encoding: .utf8)
            }
            let succeeded = process.terminationStatus == 0
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                self.refreshAfterAction()
                if succeeded {
                    self.actionText = nil
                    self.openURL(url)
                } else {
                    self.actionText = "起動に失敗しました。ログを確認してください"
                }
            }
        }
    }

    private func runThenOpenFile(_ command: String, filePath: String, label: String? = nil) {
        actionText = label
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "(\n\(command)\n) >/tmp/mulmo-control-action.log 2>&1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                try? "failed: \(error)\n".write(toFile: "/tmp/mulmo-control-action.log", atomically: true, encoding: .utf8)
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
        // 走らせる前の実測値を控える。報告はこれと更新後の値の差で作る。
        // 「これから上がるはずの版」を報告に使うと、上がらなかった物まで
        // 上がったことになってしまう。
        beforeVersions = Dictionary(
            updateItems.map { ($0.id, $0.current) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// 更新後に実測し、動いた物と動かなかった物を分けて返す。
    private func measureUpdateOutcome() -> (moved: [String], stalled: [String]) {
        guard let attempted = pendingUpdateReport else { return ([], []) }
        var moved: [String] = []
        var stalled: [String] = []
        for item in attempted {
            let before = beforeVersions[item.id] ?? item.current
            let after = updateItems.first(where: { $0.id == item.id })?.current ?? before
            if after != before {
                moved.append("\(item.displayName): \(before) → \(after)")
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
            lines.append("ログ: \(homeDir)/Documents/Codex/SwiftBarLogs")
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

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
        let key = "\(status.installedCommit)->\(status.latestCommit)"
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
                .foregroundStyle(model.titleColor)
                .font(AppFont.section)
                .accessibilityLabel(model.menuTitle)
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
                    ProgressView()
                        .scaleEffect(0.62)
                    Text(actionText)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.secondaryText)
                    Spacer()
                    if actionText.contains("失敗") {
                        Button("ログ", action: model.openActionLog)
                            .buttonStyle(.plain)
                            .font(AppFont.action)
                            .foregroundStyle(Palette.accent)
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
                    .foregroundStyle(Palette.accent)
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

struct UpdateToolbar: View {
    @ObservedObject var model: ControlModel

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

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                Text(statusDetail)
                    .font(AppFont.small)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button("確認", action: model.checkAllUpdates)
                .buttonStyle(.plain)
                .font(AppFont.action)
                .foregroundStyle(isUnknown ? .white : Palette.secondaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isUnknown ? Palette.accent : Palette.controlFill, in: Capsule())
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

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
/// 新機能の説明は公式ガイドにあるので、そこへ1クリックで行けた方がいい。
struct LinkedText: View {
    let text: String

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
                    HStack(spacing: 4) {
                        if !block.body.isEmpty {
                            Text(block.body)
                                .font(AppFont.small)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        Link("新機能を見る", destination: url)
                            .font(AppFont.small)
                            .foregroundStyle(Palette.accent)
                    }
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
                subtitle: model.mcInstalled ? (model.mcRunning ? "動作中・ブラウザで使えます" : "停止中") : "未インストール",
                isRunning: model.mcRunning,
                isAvailable: model.mcInstalled,
                accent: Palette.accent,
                inactiveTitle: model.mcInstalled ? "起動" : "入手",
                inactiveSystemImage: model.mcInstalled ? "play.fill" : "arrow.up.right",
                openAction: model.openMC,
                startAction: model.mcInstalled ? model.startMC : model.openMCRepo,
                stopAction: model.stopMC,
                restartAction: model.restartMC
            ) {
                if model.mcInstalled {
                    LogDisclosure(action: model.openMCLogs)
                } else {
                    Button("入手", action: model.openMCRepo)
                }
            }
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
        switch item.status {
        case "current":
            return "最新 \(item.current)"
        case "update":
            return "\(item.current) → \(item.latest)"
        default:
            return "導入済み"
        }
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
                    .foregroundStyle(Palette.accent)
            }
            .padding(14)
            .frame(width: 190)
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
                    SetupRow(
                        title: "スマホ連携",
                        detail: model.remoteHost.detail,
                        ok: model.remoteHost.state == "online",
                        buttonTitle: model.remoteHost.isOffline ? "繋ぎ直す"
                            : (model.remoteHost.neverConnected ? "繋ぎ方を見る" : nil),
                        action: model.remoteHost.isOffline ? model.reconnectRemoteHost : model.openMT
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
                SetupRow(title: "ログイン時起動・落ちたら再起動", detail: model.reviveEnabled ? "オン" : "オフ", ok: model.reviveEnabled)
            }
            Hairline()
                .padding(.vertical, 2)
            Text("最新版")
                .font(AppFont.section)
                .foregroundStyle(Palette.primaryText)
            VStack(spacing: 7) {
                SetupRow(title: "Mulmo Control", detail: selfUpdateDetail(model.selfUpdate), ok: model.selfUpdate.status == "current")
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
        }
        .padding(13)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func selfUpdateDetail(_ status: SelfUpdateStatus) -> String {
        switch status.status {
        case "current":
            return "最新"
        case "update":
            return "更新あり"
        case "unknown":
            return "未確認"
        default:
            return status.detail.isEmpty ? "未確認" : status.detail
        }
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
                        .foregroundStyle(Palette.accent)
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
        switch item.status {
        case "current":
            return "最新 \(item.current)"
        case "update":
            return "\(item.current) → \(item.latest)"
        default:
            return "最新版未確認"
        }
    }
}

struct SetupRow: View {
    let title: String
    let detail: String
    let ok: Bool
    var buttonTitle: String?
    var action: (() -> Void)?

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
                    .foregroundStyle(Palette.accent)
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
        switch item.status {
        case "current":
            return "最新 \(item.current)"
        case "update":
            return "\(item.current) → \(item.latest)"
        case "missing":
            return "未導入"
        default:
            return "未確認 \(item.current)"
        }
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
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isRunning ? accent : Color.secondary.opacity(0.35))
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
                    } else {
                        Spacer()
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

enum Palette {
    static let primaryText = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let secondaryText = Color(red: 0.43, green: 0.44, blue: 0.48)
    static let panelFill = Color.white.opacity(0.30)
    static let controlFill = Color(red: 0.47, green: 0.47, blue: 0.50).opacity(0.16)
    static let hairline = Color.black.opacity(0.13)
    static let accent = Color(red: 0.00, green: 0.48, blue: 0.78)
    static let ok = Color(red: 0.20, green: 0.76, blue: 0.36)
    static let warn = Color(red: 0.90, green: 0.58, blue: 0.18)
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

func readRemoteHostStatus() -> RemoteHostStatus {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: remoteHostPath)),
          let status = try? JSONDecoder().decode(RemoteHostStatus.self, from: data) else {
        return RemoteHostStatus(checkedAt: "", state: "unknown", hasSession: false, detail: "未確認")
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
        return SelfUpdateStatus(
            checkedAt: "",
            status: "unknown",
            installedCommit: "unknown",
            latestCommit: "unknown",
            detail: "未確認"
        )
    }
    return status
}

func readLastUpdateSummary() -> String {
    guard let value = try? String(contentsOfFile: lastUpdateSummaryPath, encoding: .utf8) else {
        return ""
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}
