import LooiKit
import SwiftUI

struct SettingsRootView: View {
    let session: LooiSession
    let openDeveloper: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Looi") {
                    LabeledContent("Connection", value: session.state.description)

                    if let battery = session.sensor.batteryPercent {
                        LabeledContent("Battery", value: "\(battery)%")
                    }

                    Button("Forget Pairing", role: .destructive) {
                        session.forgetPairing()
                    }
                }

                Section("Developer") {
                    Button {
                        openDeveloper()
                    } label: {
                        Label("Open DevTools", systemImage: "hammer")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsRootView(session: LooiBootstrap.shared.session, openDeveloper: {})
}
