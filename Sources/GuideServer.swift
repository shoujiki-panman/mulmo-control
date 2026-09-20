import Foundation
import Network
import SwiftUI

/// MulmoTerminal 画面のホバーガイド（Tampermonkey のユーザースクリプト）を
/// このアプリから ON/OFF するための口。Issue #185。
///
/// ユーザースクリプト側が http://127.0.0.1:34599/mt-guide を 5秒ごとに GET し、
/// {"on":true|false} に追従する。こちらは状態を UserDefaults に持ち、
/// どのパスに対しても同じ JSON を返すだけの極小サーバーを立てる。
///
/// ポートが塞がっていたら黙って諦める（ガイドはユーザースクリプト単体でも
/// 「?」ボタンから切り替えられるので、アプリの起動を止めるほどのことではない）。
final class GuideServer {
    static let shared = GuideServer()
    static let defaultsKey = "mulmo-control.mt-hover-guide-on"
    static let port: UInt16 = 34599

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "mulmo-control.guide-server")

    /// 既定は ON。ユーザースクリプト側の既定（localStorage 未設定=ON）と揃えている。
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        // ループバック固定。外から叩ける必要はない。
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        guard let l = try? NWListener(using: params) else { return }
        listener = l
        l.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.listener?.cancel()
                self?.listener = nil
            }
        }
        l.start(queue: queue)
    }

    /// リクエストの中身は見ない（パスが何であれ答えは1つ）。読み捨ててから返す。
    /// 先に送ると、クライアントが書き終える前の RST で fetch が失敗することがある。
    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
            let body = #"{"on":\#(GuideServer.isOn)}"#
            let head = [
                "HTTP/1.1 200 OK",
                "Content-Type: application/json",
                "Access-Control-Allow-Origin: *",
                "Content-Length: \(body.utf8.count)",
                "Connection: close",
                "", body,
            ].joined(separator: "\r\n")
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }
}

/// MulmoTerminal の前に立つ中継（Issue #207）。画面の HTML にだけガイドを差し込む。
///
/// 画面ガイドは最初ブラウザ拡張（Tampermonkey）で描く作りだったが、本人は拡張を
/// 入れない方針だった。中継の中身と門番は scripts/mulmoterminal-guide-proxy.mjs が
/// 持つ。ここは立てる・生きているかを見る・止めるだけ。
///
/// **「開く」を押したときにだけ立てる。** ガイドを使わない人の Mac に、常駐の
/// プロセスを1本増やさない。立てられなければ呼ぶ側は直接開く（中継が無いと
/// MulmoTerminal が開けない、という形にはしない）。
final class GuideProxy: @unchecked Sendable {
    static let shared = GuideProxy()
    /// 中継の待ち受け。**scripts/mulmoterminal-guide-proxy.mjs の既定と揃える**（check.sh が見ている）。
    static let port: UInt16 = 34598
    static var url: String { "http://127.0.0.1:\(port)/" }

    private let lock = NSLock()
    private var process: Process?

    /// いま自分が立てた中継が動いているか。**ポートを叩かずにプロセスだけ見る。**
    /// 画面は5秒ごとに巡回するので、そのたびに通信すると電池を食う（Issue #38）。
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    /// 中継が答えるか。自分が立てたものでも、前回アプリが落ちて残ったものでもよい。
    static func isServing() -> Bool {
        guard let url = URL(string: "\(url)__mulmo-guide.js") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 0.5)
        request.setValue("127.0.0.1:\(port)", forHTTPHeaderField: "Host")
        let done = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 1)
        return ok
    }

    /// 立てて、答えるまで待つ（最大2秒）。立てられなければ false。
    func ensure(node: String, script: String, upstreamPort: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if Self.isServing() { return true }
        guard FileManager.default.isExecutableFile(atPath: node),
              FileManager.default.fileExists(atPath: script) else { return false }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: node)
        child.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        // MulmoTerminal のセルから起動されていると PORT を持っている（#141）。
        // 中継は自分の名前の変数しか読まないが、持ち込まない。
        env.removeValue(forKey: "PORT")
        env["GUIDE_LISTEN"] = String(Self.port)
        env["GUIDE_UPSTREAM_PORT"] = String(upstreamPort)
        child.environment = env
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try child.run() } catch { return false }
        process = child
        for _ in 0..<20 {
            if Self.isServing() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// 自分が立てたものだけ止める。人の立てたプロセスには触らない。
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        process?.terminate()
        process = nil
    }
}

/// 運用タブに置くトグル行。台紙は持たない — `SettingsGroup` の中に
/// 並ぶので、器は親が1枚だけ持つ（Issue #192）。
struct GuideToggleRow: View {
    /// 中継が立っているか。立っていれば**どのアドレスで出ているか**を書く（Issue #209）。
    /// 「開く」で新しい窓が増えるので、前から開いていた窓を見たまま「出ない」と
    /// 読めてしまう。実際そうなった。
    let serving: Bool
    @AppStorage(GuideServer.defaultsKey) private var on: Bool = true

    private var detail: String {
        if !on { return "オフ（元の英語ツールチップに戻ります）" }
        return serving
            ? "127.0.0.1:\(GuideProxy.port) の画面で出ています"
            : "「開く」から開いた画面で、日本語の説明が出ます"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(on ? Palette.ok : Palette.secondaryText)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text("MulmoTerminal 画面ガイド")
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                Text(detail)
                    .font(AppFont.small)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button(on ? "やめる" : "オン") { on.toggle() }
                .buttonStyle(.plain)
                .font(AppFont.action)
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(on ? Palette.secondaryText : Palette.accent, in: Capsule())
        }
    }
}
