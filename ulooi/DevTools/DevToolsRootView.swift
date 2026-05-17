import SwiftUI

struct DevToolsRootView: View {
    @State private var central = BLECentral.shared
    @State private var log = ProbeLog.shared

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
    }
}

#Preview {
    DevToolsRootView()
}
