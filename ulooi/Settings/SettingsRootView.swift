import LooiKit
import SwiftUI

struct SettingsRootView: View {
    let session: LooiSession
    let mode: ModeController
    let director: PresenceDirector
    let openDeveloper: () -> Void

    @AppStorage("ulooi_face_theme") private var selectedTheme: String = FaceTheme.classicWallE.rawValue

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
                        mode.resetOnboardingForTesting()
                    }
                }

                Section("Looi Face Theme") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(FaceTheme.allCases) { theme in
                                let isSelected = selectedTheme == theme.rawValue
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                        selectedTheme = theme.rawValue
                                    }
                                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                                    haptic.impactOccurred()
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(LinearGradient(
                                                    colors: theme.previewColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ))
                                                .frame(width: 14, height: 14)
                                            
                                            Spacer()
                                            
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                                    .font(.system(size: 14, weight: .bold))
                                                    .transition(.scale.combined(with: .opacity))
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Text(theme.displayName)
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(.bold)
                                            .foregroundStyle(isSelected ? .primary : .secondary)
                                        
                                        Text(theme.description)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(height: 28, alignment: .topLeading)
                                    }
                                    .padding(12)
                                    .frame(width: 145, height: 110)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(isSelected ? Color(.systemBackground) : Color(.secondarySystemGroupedBackground))
                                            .shadow(color: isSelected ? .black.opacity(0.15) : .clear, radius: 4, x: 0, y: 2)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(
                                                isSelected ? LinearGradient(colors: theme.previewColors, startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom),
                                                lineWidth: isSelected ? 2 : 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }

                Section {
                    if let active = director.testExpressionOverride {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("表情锁定中")
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Text(expressionDisplayName(for: active))
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    director.testExpressionOverride = nil
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                Text("恢复自动状态")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        .transition(.slide.combined(with: .opacity))
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(testExpressions, id: \.self) { expr in
                            let isSelected = director.testExpressionOverride == expr
                            let config = expressionDisplayConfig(for: expr)
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    if isSelected {
                                        director.testExpressionOverride = nil
                                    } else {
                                        director.testExpressionOverride = expr
                                    }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Text(config.icon)
                                        .font(.system(size: 28))
                                        .scaleEffect(isSelected ? 1.2 : 1.0)
                                        .offset(y: isSelected ? -2 : 0)
                                    
                                    Text(config.name)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 70)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? 
                                              LinearGradient(colors: config.colors, startPoint: .topLeading, endPoint: .bottomTrailing) :
                                              LinearGradient(colors: [Color(.secondarySystemGroupedBackground)], startPoint: .top, endPoint: .bottom))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isSelected ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1.5)
                                        .shadow(color: isSelected ? config.colors.first ?? .clear : .clear, radius: 4, x: 0, y: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("小表情调试 (Looi Emotion Center)")
                } footer: {
                    Text("点击任意表情，Looi 将实时展示特定面部动画，并同步合成本地科幻音效与马达触感。")
                        .font(.system(size: 11))
                }

                Section("UCLAW Desktop") {
                    if let serverName = SecureStorage.shared.pairedServerName {
                        LabeledContent {
                            Text(serverName)
                                .font(.system(.body, design: .monospaced))
                        } label: {
                            Label("Paired Host", systemImage: "desktopcomputer")
                        }
                        
                        LabeledContent {
                            Text(TransportManager.shared.connectionState.rawValue)
                                .fontWeight(.medium)
                                .foregroundStyle(TransportManager.shared.connectionState == .connected ? .green : .orange)
                        } label: {
                            Label("Status", systemImage: "wifi")
                        }
                        
                        if let rtt = TransportManager.shared.roundTripTimeMs {
                            LabeledContent {
                                Text(String(format: "%.1f ms", rtt))
                                    .font(.system(.body, design: .monospaced))
                            } label: {
                                Label("Latency", systemImage: "gauge.with.needle")
                            }
                        }
                        
                        Button(role: .destructive) {
                            TransportManager.shared.disconnect()
                            SecureStorage.shared.wipeCredentials()
                        } label: {
                            Label("Unpair Desktop", systemImage: "link.badge.plus")
                                .foregroundStyle(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No paired desktop device found")
                                .font(.system(.headline, design: .rounded))
                            Text("Pair with UCLAW Desktop brain to unlock autonomous AI modes.")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
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

    private let testExpressions: [FaceExpression] = [
        .happy, .celebration, .victory, .drinking,
        .cool, .cute, .surprised, .fear,
        .ashamed, .shy, .idle, .sleepy,
        .cautious, .looking, .offline
    ]

    private func expressionDisplayName(for expr: FaceExpression) -> String {
        switch expr {
        case .idle: return "默认待机 🤖"
        case .happy: return "开心 😄"
        case .surprised: return "惊讶 😲"
        case .sleepy: return "困倦 😴"
        case .cautious: return "警惕 ⚠️"
        case .looking: return "寻找 🔍"
        case .offline: return "离线 🔌"
        case .celebration: return "庆祝 🎉"
        case .victory: return "胜利 🏆"
        case .drinking: return "微醺 🍷"
        case .cool: return "装酷 😎"
        case .cute: return "卖萌 ❤️"
        case .fear: return "恐惧 😨"
        case .ashamed: return "惭愧 😓"
        case .shy: return "害羞 😊"
        }
    }

    private func expressionDisplayConfig(for expr: FaceExpression) -> (name: String, icon: String, colors: [Color]) {
        switch expr {
        case .idle:
            return ("待机", "🤖", [.blue, .cyan])
        case .happy:
            return ("开心", "😄", [.yellow, .orange])
        case .surprised:
            return ("惊讶", "😲", [.mint, .cyan])
        case .sleepy:
            return ("困倦", "😴", [.blue.opacity(0.8), .purple.opacity(0.8)])
        case .cautious:
            return ("警惕", "⚠️", [.orange, .red])
        case .looking:
            return ("寻找", "🔍", [.cyan, .teal])
        case .offline:
            return ("离线", "🔌", [.gray, .black])
        case .celebration:
            return ("庆祝", "🎉", [.orange, .red])
        case .victory:
            return ("胜利", "🏆", [.yellow, .orange])
        case .drinking:
            return ("微醺", "🍷", [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.8, green: 0.1, blue: 0.3)])
        case .cool:
            return ("装酷", "😎", [.white.opacity(0.8), .gray])
        case .cute:
            return ("卖萌", "🐱", [Color(red: 1.0, green: 0.6, blue: 0.8), Color(red: 1.0, green: 0.3, blue: 0.5)])
        case .fear:
            return ("恐惧", "😨", [.purple, .blue])
        case .ashamed:
            return ("惭愧", "😓", [.gray, .blue.opacity(0.6)])
        case .shy:
            return ("害羞", "😳", [Color(red: 1.0, green: 0.65, blue: 0.65), Color(red: 1.0, green: 0.35, blue: 0.55)])
        }
    }
}

#Preview {
    SettingsRootView(
        session: LooiBootstrap.shared.session,
        mode: ModeController(),
        director: PresenceDirector(session: LooiBootstrap.shared.session),
        openDeveloper: {}
    )
}
