import SwiftUI

struct DevToolsRootView: View {
    // Shared singletons — use plain `let`, not `@State`. `@State` for `@Observable`
    // is for view-CREATED instances; using it on a shared singleton can break the
    // observation propagation through child views (root cause of M0.5 "Logs tab
    // never updates" bug). Plain `let` correctly registers property reads in body.
    let central = BLECentral.shared
    let log = ProbeLog.shared

    var body: some View {
        TabView {
            ScanView(central: central, log: log)
                .tabItem { Label("Scan", systemImage: "wave.3.right") }

            InspectView(central: central, log: log)
                .tabItem { Label("Inspect", systemImage: "list.bullet.rectangle") }

            CommandView(central: central, log: log)
                .tabItem { Label("Send", systemImage: "paperplane") }

            SenseView(central: central, log: log)
                .tabItem { Label("Sense", systemImage: "hand.tap") }

            LogsView(log: log)
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .overlay(alignment: .top) {
            // Build watermark — verify Cmd+R deployed the right code. See BuildInfo.swift.
            Text(BuildInfo.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.yellow.opacity(0.92))
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 4)
                .allowsHitTesting(false)
        }
        .onAppear {
            DevLog.event("DevToolsRootView appeared — build=\(BuildInfo.label)", channel: DevLog.ui)
        }
    }
}

#Preview {
    DevToolsRootView()
}
