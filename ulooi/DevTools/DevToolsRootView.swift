import LooiKit
import SwiftUI

struct DevToolsRootView: View {
    // Plain `let` on a shared @Observable singleton — not `@State`. Using @State
    // on an externally-shared @Observable breaks observation propagation to child
    // views (M0.5 "Logs tab never updates" lesson). Plain `let` registers property
    // reads correctly in body.
    let session = LooiBootstrap.shared.session
    let transport = LooiBootstrap.shared.transport
    let log = ProbeLog.shared

    var body: some View {
        TabView {
            ScanView(transport: transport, session: session, log: log)
                .tabItem { Label("Scan", systemImage: "wave.3.right") }

            InspectView(session: session, log: log)
                .tabItem { Label("Inspect", systemImage: "list.bullet.rectangle") }

            CommandView(session: session, log: log)
                .tabItem { Label("Send", systemImage: "paperplane") }

            SenseView(session: session, log: log)
                .tabItem { Label("Sense", systemImage: "hand.tap") }

            P2PDesktopDevView()
                .tabItem { Label("Desktop", systemImage: "desktopcomputer") }

            LogsView(log: log)
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                // Build watermark — verify Cmd+R deployed the right code.
                Text(BuildInfo.label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.yellow.opacity(0.92))
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 4)
                    .allowsHitTesting(false)

                // Connection state banner — visible only when connected.
                // Always shows across all tabs so the user has a constant
                // visual confirmation of the BLE session.
                ConnectionBanner(session: session)
            }
        }
        .onAppear {
            DevLog.event("DevToolsRootView appeared — build=\(BuildInfo.label)", channel: DevLog.ui)
        }
        // Bridge LooiKit's OSLog-only state transitions into the in-app
        // ProbeLog so the Logs tab actually shows them. LooiKit logs to
        // os.Logger directly (no DevLog dep — see Task 2 design); without
        // this bridge, state: handshaking → ready etc. only appear in
        // Xcode console, not in the app's own log surface.
        .onChange(of: session.state.description) { _, newDescription in
            DevLog.event("session.state → \(newDescription)", channel: DevLog.ble)
        }
    }
}

#Preview {
    DevToolsRootView()
}
