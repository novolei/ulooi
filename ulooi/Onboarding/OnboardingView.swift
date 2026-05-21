import LooiKit
import SwiftUI
import CryptoKit

struct OnboardingView: View {
    let session: LooiSession
    let continueInPhoneMode: () -> Void
    let openSettings: () -> Void

    // --- Onboarding Presentation States ---
    @State private var showingBLERitual = false
    @State private var showingDesktopPairing = false
    @State private var showingVerification = false
    
    // --- Cryptographic Handshake Cache ---
    @State private var pairingParams: PairingParameters? = nil
    @State private var derivedHandshakeKey: SymmetricKey? = nil
    @State private var clientEphPrivateKey: Curve25519.KeyAgreement.PrivateKey? = nil
    @State private var pairingRequestModel: PairingRequest? = nil
    @State private var verificationCode: String = ""

    // --- Core Portal Animation States ---
    @State private var coreRotation1 = 0.0
    @State private var coreRotation2 = 0.0
    @State private var coreRotation3 = 0.0
    @State private var coreScalePulse: CGFloat = 0.98
    @State private var buttonShimmerOffset: CGFloat = -1.5

    var body: some View {
        NavigationStack {
            ZStack {
                // Futuristic deep-space background
                Color.black.ignoresSafeArea()
                
                // Fine digital-mesh spatial grid overlay
                GeometryReader { proxy in
                    Canvas { context, size in
                        context.opacity = 0.07
                        let gridSpacing: CGFloat = 50
                        var x: CGFloat = 0
                        while x < size.width {
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(path, with: .color(.cyan), lineWidth: 0.5)
                            x += gridSpacing
                        }
                        var y: CGFloat = 0
                        while y < size.height {
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            context.stroke(path, with: .color(.cyan), lineWidth: 0.5)
                            y += gridSpacing
                        }
                    }
                }
                .ignoresSafeArea()
                
                // Warm ambient color gradients
                RadialGradient(
                    colors: [.orange.opacity(0.12), .cyan.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 360
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    
                    // --- THE LOOI VIRTUAL CORE OF CONSCIOUSNESS ---
                    ZStack {
                        // Pulsing background plasma aura
                        Circle()
                            .fill(RadialGradient(
                                colors: [.orange.opacity(0.25), .cyan.opacity(0.1), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 130
                            ))
                            .frame(width: 260, height: 260)
                            .scaleEffect(coreScalePulse)
                        
                        // Ring 1: Looi Gold & Orange Orbit (Yaw rotation)
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.orange, .yellow, .orange.opacity(0.12), .orange],
                                    center: .center
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 180, height: 180)
                            .rotationEffect(.degrees(coreRotation1))
                        
                        // Ring 2: Cyber-Cyan Node Axis
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.cyan, .blue, .cyan.opacity(0.18), .cyan],
                                    center: .center
                                ),
                                lineWidth: 1.5
                            )
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(coreRotation2))
                            .scaleEffect(1.0 + (coreScalePulse - 1.0) * 0.4)
                        
                        // Ring 3: Organic Matrix Mint Channel
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.mint, .green, .mint.opacity(0.2), .mint],
                                    center: .center
                                ),
                                lineWidth: 1.0
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(coreRotation3))
                        
                        // Holographic center singularity
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white, .orange.opacity(0.85), .cyan.opacity(0.35), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 35
                                )
                            )
                            .frame(width: 70, height: 70)
                            .shadow(color: .orange.opacity(0.4), radius: 12)
                            .scaleEffect(coreScalePulse)
                    }
                    .frame(height: 240)
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    // Gateway Typography & Core Mission Statement
                    VStack(spacing: 14) {
                        Text("MEET LOOI")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .kerning(4)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        Text("When connected, this phone becomes Looi's expressive robotic face. When away, it stays a calm, sci-fi companion app.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4.5)
                            .padding(.horizontal, 36)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 36)
                    
                    // Premium Interaction Buttons with responsive micro-animations
                    VStack(spacing: 16) {
                        // "Awaken Looi Robot" - Capsule Glassmorphic Shimmer button
                        Button {
                            showingBLERitual = true
                        } label: {
                            ZStack {
                                // Background glassmorphic gold fill
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .yellow],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: .orange.opacity(0.38), radius: 10, x: 0, y: 5)
                                
                                // Glowing active bezel
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.7), .clear, .white.opacity(0.35)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                                
                                // Shimmer reflection overlay
                                GeometryReader { btnProxy in
                                    let btnSize = btnProxy.size
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [.clear, .white.opacity(0.38), .clear],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: btnSize.width * 0.4)
                                        .offset(x: btnSize.width * buttonShimmerOffset)
                                }
                                .clipped()
                                
                                Label("Awaken Looi Robot", systemImage: "sparkles")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 32)
                        
                        // Secondary "Pair Desktop Brain" button
                        Button {
                            showingDesktopPairing = true
                        } label: {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Pair Desktop Brain")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.cyan)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(.cyan.opacity(0.24), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 32)
                        
                        // Tertiary fallback button
                        Button(action: continueInPhoneMode) {
                            Text("Use Phone Mode")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openSettings) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 10.0).repeatForever(autoreverses: false)) {
                    coreRotation1 = 360.0
                }
                withAnimation(.linear(duration: 14.0).repeatForever(autoreverses: false)) {
                    coreRotation2 = -360.0
                }
                withAnimation(.linear(duration: 18.0).repeatForever(autoreverses: false)) {
                    coreRotation3 = 360.0
                }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                    coreScalePulse = 1.05
                }
                withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: false)) {
                    buttonShimmerOffset = 1.6
                }
            }
            // --- Interactive sheets & full-screen pairing flows ---
            .fullScreenCover(isPresented: $showingBLERitual) {
                BLEPairingRitualView(session: session) {
                    continueInPhoneMode()
                }
            }
            .sheet(isPresented: $showingDesktopPairing) {
                QRScannerView { uri in
                    self.showingDesktopPairing = false
                    
                    // Parse pairing parameters
                    guard let params = PairingService.shared.parsePairingURI(uri) else {
                        print("❌ Onboarding: Failed to parse scanned QR URI")
                        return
                    }
                    
                    do {
                        let clientName = UIDevice.current.name
                        let result = try PairingService.shared.preparePairingRequest(params: params, clientName: clientName)
                        
                        self.pairingParams = params
                        self.pairingRequestModel = result.0
                        self.derivedHandshakeKey = result.1
                        self.clientEphPrivateKey = result.2
                        self.verificationCode = PairingService.shared.computeVerificationCode(derivedKey: result.1)
                        
                        // Settle slightly, then present verification view
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            self.showingVerification = true
                        }
                    } catch {
                        print("❌ Onboarding: Failed to compute ECDH request: \(error.localizedDescription)")
                    }
                } onCancel: {
                    self.showingDesktopPairing = false
                }
            }
            .sheet(isPresented: $showingVerification) {
                if let request = pairingRequestModel,
                   let derivedKey = derivedHandshakeKey,
                   let params = pairingParams {
                    PairingVerificationView(
                        verificationCode: verificationCode,
                        serverName: params.host,
                        isHandshaking: false,
                        onConfirm: {
                            // In real or simulator mode: connect socket and send pairing payload
                            let wsScheme = "ws"
                            var sanitizedHost = params.host
                            if sanitizedHost.hasSuffix(".") {
                                sanitizedHost.removeLast()
                            }
                            
                            if let url = URL(string: "\(wsScheme)://\(sanitizedHost):\(params.port)/ws") {
                                TransportManager.shared.isSimulatorMode = (params.host == "UCLAW-Simulator")
                                TransportManager.shared.connect(url: url)
                                
                                // Send pairing.request envelope
                                let envelope = WireEnvelope(
                                    id: UUID().uuidString,
                                    src: "ulooi-client-\(UUID().uuidString.prefix(6))",
                                    kind: "pairing.request",
                                    payload: .pairingRequest(request)
                                )
                                
                                // Register response handler
                                TransportManager.shared.registerHandler { responseEnvelope in
                                    if responseEnvelope.kind == "pairing.response" {
                                        if case let .pairingResponse(resp) = responseEnvelope.payload {
                                            do {
                                                let success = try PairingService.shared.completePairing(
                                                    response: resp,
                                                    params: params,
                                                    derivedKey: derivedKey,
                                                    clientEphPublicKeyData: request.clientEphPk
                                                )
                                                if success {
                                                    print("✅ Onboarding: Handshake success! Redirecting...")
                                                }
                                            } catch {
                                                print("❌ Onboarding: Complete pairing error: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                }
                                
                                // Fire request immediately
                                TransportManager.shared.sendEnvelope(envelope)
                            }
                            
                            self.showingVerification = false
                            self.continueInPhoneMode()
                        },
                        onCancel: {
                            self.showingVerification = false
                        }
                    )
                } else {
                    VStack {
                        Text("Pairing Cryptography Setup Failed")
                        Button("Dismiss") { showingVerification = false }
                    }
                }
            }
        }
    }
}

#Preview {
    OnboardingView(
        session: LooiBootstrap.shared.session,
        continueInPhoneMode: {},
        openSettings: {}
    )
}
