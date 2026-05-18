import LooiKit
import SwiftUI

struct EmbodiedHomeView: View {
    let director: PresenceDirector
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            GeometricFaceView(model: director.face)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 160)
                bottomControls
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            statusPill

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.12), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .accessibilityLabel("Settings")
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            Text(director.face.line)
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: 520)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.18), in: Capsule())

            HStack(spacing: 12) {
                gestureButton(.wave, title: "招呼", systemImage: "hand.wave.fill")
                gestureButton(.lookAtMe, title: "看我", systemImage: "eye.fill")
                gestureButton(.sleep, title: "睡觉", systemImage: "moon.zzz.fill")
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background(.white.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }

    private var statusText: String {
        switch director.state {
        case .disconnected:
            return "Disconnected"
        case .lookingForBody, .booting:
            return "Finding Looi"
        case .sleeping:
            return "Sleeping"
        case .suspended:
            return "Safety"
        default:
            return "Connected"
        }
    }

    private var statusColor: Color {
        switch director.state {
        case .disconnected:
            return .white.opacity(0.38)
        case .suspended, .errorRecoverable:
            return .pink
        case .sleeping:
            return .cyan
        default:
            return .yellow
        }
    }

    private func gestureButton(_ kind: GestureKind, title: String, systemImage: String) -> some View {
        Button {
            director.perform(kind)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 21)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 92, height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityLabel(title)
    }
}

#Preview {
    EmbodiedHomeView(
        director: PresenceDirector(session: LooiBootstrap.shared.session),
        openSettings: {}
    )
}
