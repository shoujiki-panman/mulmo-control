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

/// 運用タブに置くトグル行。見た目は ClaudeLoginCard と同じパネル型に揃える。
struct GuideToggleRow: View {
    @AppStorage(GuideServer.defaultsKey) private var on: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(on ? Palette.ok : Palette.secondaryText)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text("MulmoTerminal 画面ガイド")
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Palette.primaryText)
                Text(on ? "カーソルを合わせると日本語の説明が出ます" : "オフ（元の英語ツールチップに戻ります）")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
