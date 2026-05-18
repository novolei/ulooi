import LooiKit
import SwiftUI

struct OnboardingView: View {
    let session: LooiSession

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 14) {
                Text("Meet Looi")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("When the little body is connected, this phone becomes Looi's face. When Looi is away, it stays a calm companion app.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Landscape with Looi nearby opens Face Mode.", systemImage: "rectangle.landscape.rotate")
                Label("Portrait or away keeps the normal app ready.", systemImage: "iphone")
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)

            Button {
                session.startScanAndConnect()
            } label: {
                Label(buttonTitle, systemImage: "wave.3.right")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.state.isInProgress)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    private var buttonTitle: String {
        session.state.isInProgress ? "Finding Looi" : "Find Looi"
    }
}

#Preview {
    OnboardingView(session: LooiBootstrap.shared.session)
}
