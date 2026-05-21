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
                    OnboardingView(
                        session: session,
                        continueInPhoneMode: {
                            mode.completeOnboarding()
                        },
                        openSettings: {
                            showingSettings = true
                        }
                    )
                case .faceMode:
                    EmbodiedHomeView(director: director) {
                        showingSettings = true
                    }
                case .standalone:
                    StandaloneHomeView(session: session, director: director) {
                        showingSettings = true
                    }
                case .developer:
                    developerSurface
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsRootView(session: session, mode: mode, director: director) {
                mode.developerOpen = true
                showingSettings = false
            }
        }
        .onChange(of: session.state) { _, newState in
            director.reconcileSessionState()
            completeOnboardingIfReady(newState)
        }
    }

    private var developerSurface: some View {
        ZStack(alignment: .topTrailing) {
            DevToolsRootView()

            Button {
                mode.developerOpen = false
            } label: {
                Label("Done", systemImage: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("Close DevTools")
        }
    }

    private func completeOnboardingIfReady(_ state: SessionState) {
        guard !mode.onboardingComplete, state == .ready else { return }
        mode.completeOnboarding()
    }
}

#Preview {
    ContentView()
}
