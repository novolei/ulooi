import SwiftUI

/// Elegant confirmation dialogue showing computed 4-digit security code.
/// Displays smooth glassmorphic cards, transition animations, and haptic feedback confirmation.
public struct PairingVerificationView: View {
    let verificationCode: String
    let serverName: String
    let isHandshaking: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var animatePulse = false
    
    public init(
        verificationCode: String,
        serverName: String,
        isHandshaking: Bool,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.verificationCode = verificationCode
        self.serverName = serverName
        self.isHandshaking = isHandshaking
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(spacing: 34) {
            Spacer()
                .frame(height: 10)
            
            // --- Top Header ---
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce.up, options: .nonRepeating)
                    .scaleEffect(animatePulse ? 1.06 : 0.98)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            animatePulse = true
                        }
                    }
                
                Text("安全配对验证")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("正在与 [\(serverName)] 建立加密信道")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            // --- 4-Digit Code Grid ---
            if isHandshaking {
                handshakeProgressView
            } else {
                codeGridView
            }
            
            // --- Instructions ---
            VStack(spacing: 8) {
                Text("请检查 iPhone 与电脑屏幕上的四位数字是否一致")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("一致代表双方已通过 X25519 椭圆曲线安全交换密钥，信息将被全程高强度加密存储。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            // --- Action Buttons ---
            VStack(spacing: 12) {
                Button {
                    triggerHapticSuccess()
                    onConfirm()
                } label: {
                    Label("确认配对并保存", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(isHandshaking)
                
                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background(Color(.systemGroupedBackground))
    }
    
    // --- Sub-components ---
    
    private var codeGridView: some View {
        HStack(spacing: 14) {
            let digits = Array(verificationCode).map { String($0) }
            let placeholder = ["0", "0", "0", "0"]
            let items = digits.count == 4 ? digits : placeholder
            
            ForEach(0..<4, id: \.self) { idx in
                Text(items[idx])
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .frame(width: 64, height: 76)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.green.opacity(0.24), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var handshakeProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.green)
                .scaleEffect(1.2)
            
            Text("正在进行椭圆曲线 P2P 握手...")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(height: 76)
        .padding(.vertical, 8)
    }
    
    private func triggerHapticSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

#Preview {
    PairingVerificationView(
        verificationCode: "7294",
        serverName: "Ryan's Studio Mac",
        isHandshaking: false,
        onConfirm: {},
        onCancel: {}
    )
}
