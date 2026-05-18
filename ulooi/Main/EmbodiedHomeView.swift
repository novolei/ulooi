import LooiKit
import SwiftUI

struct EmbodiedHomeView: View {
    let director: PresenceDirector
    let openSettings: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let metrics = FaceModeMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let face = director.face

                ZStack {
                    GeometricFaceView(model: face)
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        topBar(metrics: metrics)
                        Spacer(minLength: metrics.middleGap)
                        bottomControls(face: face, metrics: metrics)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, metrics.topPadding)
                    .padding(.bottom, metrics.bottomPadding)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func topBar(metrics: FaceModeMetrics) -> some View {
        HStack(spacing: 12) {
            statusPill

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: metrics.settingsSize, height: metrics.settingsSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.12), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .accessibilityLabel("Settings")
        }
    }

    private func bottomControls(face: FaceModel, metrics: FaceModeMetrics) -> some View {
        VStack(spacing: metrics.controlSpacing) {
            Text(face.line)
                .font(.system(size: metrics.lineFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: 520)
                .padding(.horizontal, metrics.lineHorizontalPadding)
                .padding(.vertical, metrics.lineVerticalPadding)
                .background(.black.opacity(0.18), in: Capsule())

            HStack(spacing: metrics.buttonSpacing) {
                gestureButton(.wave, title: "招呼", systemImage: "hand.wave.fill", metrics: metrics)
                gestureButton(.lookAtMe, title: "看我", systemImage: "eye.fill", metrics: metrics)
                gestureButton(.sleep, title: "睡觉", systemImage: "moon.zzz.fill", metrics: metrics)
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

    private func gestureButton(
        _ kind: GestureKind,
        title: String,
        systemImage: String,
        metrics: FaceModeMetrics
    ) -> some View {
        let isBusy = director.activeGesture != nil
        let isActive = director.activeGesture == kind

        return Button {
            director.perform(kind)
        } label: {
            VStack(spacing: metrics.buttonLabelSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.buttonIconSize, weight: .semibold))
                    .frame(height: metrics.buttonIconSize + 3)

                Text(title)
                    .font(.system(size: metrics.buttonFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: metrics.buttonWidth, height: metrics.buttonHeight)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .foregroundStyle(.white.opacity(isBusy && !isActive ? 0.48 : 1))
        .background(buttonFill(isActive: isActive, isBusy: isBusy), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? .yellow.opacity(0.66) : .white.opacity(0.18), lineWidth: 1)
        )
        .accessibilityLabel(title)
    }

    private func buttonFill(isActive: Bool, isBusy: Bool) -> Color {
        if isActive { return .yellow.opacity(0.22) }
        if isBusy { return .white.opacity(0.08) }
        return .white.opacity(0.13)
    }
}

private struct FaceModeMetrics {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var isCompactHeight: Bool { size.height < 390 }

    var horizontalPadding: CGFloat {
        min(24, max(12, size.width * 0.045))
    }

    var topPadding: CGFloat {
        max(10, safeAreaInsets.top + (isCompactHeight ? 6 : 14))
    }

    var bottomPadding: CGFloat {
        max(10, safeAreaInsets.bottom + (isCompactHeight ? 8 : 18))
    }

    var middleGap: CGFloat {
        isCompactHeight ? 12 : 72
    }

    var settingsSize: CGFloat {
        isCompactHeight ? 40 : 44
    }

    var controlSpacing: CGFloat {
        isCompactHeight ? 10 : 16
    }

    var buttonSpacing: CGFloat {
        isCompactHeight ? 7 : 10
    }

    var lineHorizontalPadding: CGFloat {
        isCompactHeight ? 14 : 18
    }

    var lineVerticalPadding: CGFloat {
        isCompactHeight ? 7 : 10
    }

    var lineFontSize: CGFloat {
        isCompactHeight ? 16 : 19
    }

    var buttonWidth: CGFloat {
        let available = max(0, size.width - horizontalPadding * 2 - buttonSpacing * 2)
        return min(isCompactHeight ? 94 : 104, max(72, floor(available / 3)))
    }

    var buttonHeight: CGFloat {
        isCompactHeight ? 50 : 58
    }

    var buttonIconSize: CGFloat {
        isCompactHeight ? 16 : 18
    }

    var buttonFontSize: CGFloat {
        isCompactHeight ? 13 : 14
    }

    var buttonLabelSpacing: CGFloat {
        isCompactHeight ? 3 : 5
    }
}

#Preview {
    EmbodiedHomeView(
        director: PresenceDirector(session: LooiBootstrap.shared.session),
        openSettings: {}
    )
}
