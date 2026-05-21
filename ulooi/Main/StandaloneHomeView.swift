import LooiKit
import SwiftUI

struct StandaloneHomeView: View {
    let session: LooiSession
    let director: PresenceDirector
    let openSettings: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header

                        VStack(alignment: .leading, spacing: 14) {
                            infoRow(title: statusText, systemImage: "antenna.radiowaves.left.and.right", color: statusColor)
                            infoRow(title: batteryText, systemImage: "battery.75", color: .green)
                            infoRow(title: orientationText(for: proxy.size), systemImage: "rectangle.landscape.rotate", color: .cyan)
                        }
                        .font(.system(size: 16, weight: .medium, design: .rounded))

                        reconnectButton

                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("ulooi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .background(Color(.systemBackground))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ulooi")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(director.face.line)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reconnectButton: some View {
        Button {
            director.wake()
            session.startScanAndConnect()
        } label: {
            Label(reconnectTitle, systemImage: "wave.3.right")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var reconnectTitle: String {
        session.state.isReady ? "重新寻找 Looi" : "寻找 Looi"
    }

    private func infoRow(title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var statusText: String {
        switch session.state {
        case .ready:
            return "小身体已连接"
        case .disconnected:
            return "Looi 不在附近"
        case .scanning:
            return "正在寻找附近的 Looi"
        case .connecting, .discovering, .handshaking:
            return "正在连接 Looi"
        case .reconnecting:
            return "正在重新连接 Looi"
        }
    }

    private var statusColor: Color {
        session.state.isReady ? .green : .secondary
    }

    private var batteryText: String {
        if let battery = session.sensor.batteryPercent {
            return "电量 \(battery)%"
        }
        return "还没有电量读数"
    }

    private func orientationText(for size: CGSize) -> String {
        if size.width > size.height {
            return "横屏时 Face Mode 会接管主画面"
        }
        return "当前是普通竖屏 app 模式"
    }
}

#Preview {
    StandaloneHomeView(
        session: LooiBootstrap.shared.session,
        director: PresenceDirector(session: LooiBootstrap.shared.session),
        openSettings: {}
    )
}
