import SwiftUI
import LooiKit

struct ContentView: View {
    let session = LooiBootstrap.shared.session
    @State private var mode = ModeController()
    @State private var director = PresenceDirector(session: LooiBootstrap.shared.session)
    @State private var showingSettings = false

    var body: some View {
        GeometryReader { proxy in
            let orientation: UlooiOrientation = proxy.size.width > proxy.size.height ? .landscape : .portrait

            Group {
                switch mode.surface(session: session, orientation: orientation) {
                case .onboarding:
                    OnboardingView(session: session) {
                        mode.completeOnboarding()
                    }
                case .faceMode:
                    EmbodiedHomeView(director: director) {
                        showingSettings = true
                    }
                case .standalone:
                    StandaloneHomeView(session: session, director: director) {
                        showingSettings = true
                    }
                case .developer:
                    DevToolsRootView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsRootView(session: session) {
                mode.developerOpen = true
                showingSettings = false
            }
        }
        .onChange(of: session.state.description) {
            director.reconcileSessionState()
        }
    }
}

#Preview {
    ContentView()
}
