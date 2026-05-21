import SwiftUI
import LooiKit

/// A world-class, immersive onboarding pairing view representing the "Awakening Ritual".
/// It maps `LooiSession`'s BLE state transitions directly into visual, audio, and tactile states,
/// turning a technical Bluetooth connection into a magical "Soul & Body Fusion" experience.
public struct BLEPairingRitualView: View {
    let session: LooiSession
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // --- Starfield Particle System Models ---
    private struct Star: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let speed: Double
        let baseOpacity: Double
    }
    
    // --- UI Animation States ---
    @State private var stars: [Star] = []
    @State private var radarRotation: Double = 0.0
    @State private var coreScale: CGFloat = 1.0
    @State private var syncProgress: CGFloat = 0.0
    @State private var timer: Timer? = nil
    
    // --- Handshake Synced Step Progress ---
    @State private var handshakeStep: Int = 0
    @State private var handshakeTimer: Timer? = nil
    
    // --- Climax Climax Visual Effects ---
    @State private var showRadialFlash = false
    @State private var successBurstScale: CGFloat = 0.0
    @State private var successBurstOpacity: Double = 0.0
    @State private var showGreetingBubble = false
    @State private var typewriterText: String = ""
    
    // --- Haptics Generators ---
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    
    public init(session: LooiSession, onDismiss: @escaping () -> Void) {
        self.session = session
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            // Futuristic dark deep space background
            Color.black.ignoresSafeArea()
            
            // --- DYNAMIC STARFIELD CANVAS & COSMIC GRID ---
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSince1970
                
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    
                    guard w > 0 && h > 0 else { return }
                    
                    // Draw a subtle scifi coordinate grid in the background
                    context.opacity = 0.06
                    let gridSpacing: CGFloat = 40
                    
                    var x: CGFloat = 0
                    while x < w {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: h))
                        context.stroke(path, with: .color(.cyan), lineWidth: 0.5)
                        x += gridSpacing
                    }
                    
                    var y: CGFloat = 0
                    while y < h {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                        context.stroke(path, with: .color(.cyan), lineWidth: 0.5)
                        y += gridSpacing
                    }
                    
                    // Concentric background radar guides
                    let center = CGPoint(x: w / 2, y: h / 2)
                    for r in [120, 200, 280, 360] {
                        var path = Path()
                        path.addArc(center: center, radius: CGFloat(r), startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                        context.stroke(path, with: .color(.cyan), lineWidth: 0.5)
                    }
                    
                    // --- RENDER DRIFTING & TWINKLING STARS ---
                    for star in stars {
                        // Drift speed based on time
                        let currentX = (star.x * w - CGFloat(time * star.speed * 12)).truncatingRemainder(dividingBy: w)
                        let adjustedX = currentX < 0 ? currentX + w : currentX
                        
                        let currentY = (star.y * h - CGFloat(time * star.speed * 6)).truncatingRemainder(dividingBy: h)
                        let adjustedY = currentY < 0 ? currentY + h : currentY
                        
                        // Fluctuate opacity to twinkle
                        let twinkling = star.baseOpacity + sin(time * (star.speed * 20.0)) * 0.32
                        let opacity = max(0.12, min(1.0, twinkling))
                        
                        context.opacity = opacity
                        let rect = CGRect(x: adjustedX, y: adjustedY, width: star.size, height: star.size)
                        context.fill(Path(ellipseIn: rect), with: .color(.white))
                    }
                }
            }
            .ignoresSafeArea()
            
            // --- SCI-FI TELEMETRY HUD OVERLAY (4 CORNERS) ---
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSince1970
                let rssiVal = -42 - Int(abs(sin(time * 1.5)) * 12)
                let decOffset = cos(time * 0.5) * 0.007
                
                VStack {
                    // Top Row
                    HStack {
                        // Top-Left: RA/DEC Coordinate locks
                        VStack(alignment: .leading, spacing: 4) {
                            Text("COORD_LOCK: ACTIVE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text("RA: 18h 36m 56s")
                                .font(.system(size: 9, design: .monospaced))
                            Text("DEC: +38° 47′ \(String(format: "%.2f", 1.05 + decOffset))″")
                                .font(.system(size: 9, design: .monospaced))
                            Text("VELOCITY: 28,450 km/h")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.leading, 24)
                        
                        Spacer()
                        
                        // Top-Right: Crypto Cipher Mechanics
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("ENCRYPTION: SHIELDED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                            Text("CIPHER: CURVE25519-X25519")
                                .font(.system(size: 9, design: .monospaced))
                            Text("HASH_ALGO: SHA-256")
                                .font(.system(size: 9, design: .monospaced))
                            Text("KEY_ENTROPY: INT-98.74%")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.trailing, 24)
                    }
                    .padding(.top, 55)
                    
                    Spacer()
                    
                    // Bottom Row
                    HStack {
                        // Bottom-Left: Live Bluetooth RSSI signal tracker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BLE_LINK: MONITORING")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.yellow)
                            Text("RSSI_VAL: \(rssiVal) dBm")
                                .font(.system(size: 9, design: .monospaced))
                            Text("CH_LATENCY: 24 ms")
                                .font(.system(size: 9, design: .monospaced))
                            Text("FRAME_LOSS: 0.00%")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.leading, 24)
                        
                        Spacer()
                        
                        // Bottom-Right: Active sync buffer and states
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("STATE_SYS: DIAGNOSTICS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(coreGlowColor)
                            Text("SYNC_BUF: 1024 KB")
                                .font(.system(size: 9, design: .monospaced))
                            Text("SYS_STATE: \(sysStateStr)")
                                .font(.system(size: 9, design: .monospaced))
                            Text("CORE_LOAD: \(String(format: "%.1f", 12.4 + abs(sin(time * 0.8)) * 4.2))%")
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.trailing, 24)
                    }
                    .padding(.bottom, 115)
                }
            }
            .ignoresSafeArea()
            
            // --- Climax Golden Shockwave Ripple Overlay ---
            Circle()
                .stroke(
                    RadialGradient(
                        colors: [.yellow, .orange, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    ),
                    lineWidth: 6
                )
                .frame(width: 150, height: 150)
                .scaleEffect(successBurstScale)
                .opacity(successBurstOpacity)
                .ignoresSafeArea()
            
            // --- Active State Elements ---
            VStack {
                Spacer()
                
                // Holographic Center Core Container
                ZStack {
                    // Outer Radar Sweep Ring (Scanning phase)
                    if session.state == .scanning {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [.cyan.opacity(0.8), .cyan.opacity(0.1), .clear],
                                    center: .center
                                ),
                                lineWidth: 4
                            )
                            .frame(width: 260, height: 260)
                            .rotationEffect(.degrees(radarRotation))
                            .onAppear {
                                withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                                    radarRotation = 360.0
                                }
                            }
                        
                        // Radiating electromagnetic waves
                        Circle()
                            .stroke(.cyan.opacity(0.4), lineWidth: 1)
                            .frame(width: 320, height: 320)
                            .scaleEffect(successBurstScale == 0 ? 1.0 + (radarRotation / 360.0) : 1.0)
                            .opacity(successBurstScale == 0 ? Double(1.0 - (radarRotation / 360.0)) : 0.0)
                    }
                    
                    // Glassmorphic Cyber Core Node (Snaps on connection)
                    ZStack {
                        // Background neon glow
                        Circle()
                            .fill(coreGlowColor)
                            .frame(width: 165, height: 160)
                            .blur(radius: 28)
                        
                        // Glass Ring Bezel
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 1.5)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.85)
                            )
                            .frame(width: 140, height: 140)
                        
                        // Rotating tick dials
                        Circle()
                            .stroke(.cyan.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [4, 18]))
                            .frame(width: 116, height: 116)
                            .rotationEffect(.degrees(radarRotation * 0.5))
                        
                        // Custom Interactive Gyroscope instead of static placeholder
                        ZStack {
                            Circle()
                                .stroke(coreGlowColor.opacity(0.6), lineWidth: 1.5)
                                .frame(width: 80, height: 80)
                            
                            Circle()
                                .stroke(coreGlowColor.opacity(0.45), style: StrokeStyle(lineWidth: 1.0, dash: [6, 6]))
                                .frame(width: 66, height: 66)
                                .rotationEffect(.degrees(-radarRotation * 0.8))
                            
                            Circle()
                                .stroke(coreGlowColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 12]))
                                .frame(width: 50, height: 50)
                                .rotationEffect(.degrees(radarRotation * 1.2))
                            
                            // Glowing center singularity
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [.white, coreGlowColor, .clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 18
                                    )
                                )
                                .frame(width: 32, height: 32)
                                .shadow(color: coreGlowColor.opacity(0.6), radius: 8)
                        }
                        .opacity(0.85)
                        
                        // Neural Handshake Progress Ring
                        if session.state == .handshaking {
                            Circle()
                                .trim(from: 0, to: syncProgress)
                                .stroke(
                                    LinearGradient(
                                        colors: [.mint, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                )
                                .frame(width: 140, height: 140)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .scaleEffect(coreScale)
                    .onChange(of: session.state) { _, newState in
                        triggerStateTransitions(newState)
                    }
                }
                .frame(height: 340)
                
                Spacer()
                
                // --- Premium HUD Copy & Loading States ---
                if !showGreetingBubble {
                    VStack(spacing: 12) {
                        Text(hudTitle)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)
                        
                        Text(hudSubtitle)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .lineSpacing(2)
                            .frame(height: 50)
                            .contentTransition(.opacity)
                    }
                    .padding(.bottom, 48)
                } else {
                    Spacer()
                        .frame(height: 110)
                }
                
                // --- Cancel / Disconnect button ---
                Button {
                    handshakeTimer?.invalidate()
                    handshakeTimer = nil
                    session.disconnect()
                    onDismiss()
                    dismiss()
                } label: {
                    Text("取消唤醒")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 24)
                        .frame(height: 40)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .padding(.bottom, 28)
            }
            
            // --- CHARACTER GREETING DIALOGUE OVERLAY (ON SUCCESS) ---
            if showGreetingBubble {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // Programmatic Digital Blinking Face View
                        BlinkingLEDFaceView()
                            .frame(height: 50)
                            .padding(.top, 14)
                        
                        // Typewriter text dialog bubble
                        VStack(spacing: 8) {
                            Text("LOOI ROBOT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                            
                            Text(typewriterText)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 45)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .orange.opacity(0.24), radius: 20)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.orange.opacity(0.45), .clear, .white.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .padding(.horizontal, 32)
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            // --- Radial Awakening Gold Flash Overlay (Triggered on .ready) ---
            if showRadialFlash {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.orange.opacity(0.85), .yellow.opacity(0.45), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 400
                        )
                    )
                    .ignoresSafeArea()
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                showRadialFlash = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            populateStars()
            session.startScanAndConnect()
            startRadarPingTimer()
            triggerStateTransitions(session.state)
        }
        .onDisappear {
            stopRadarPingTimer()
            handshakeTimer?.invalidate()
            handshakeTimer = nil
            SciFiAudioSynth.shared.stop()
        }
    }
    
    // --- State Transition Logic ---
    
    private func triggerStateTransitions(_ state: SessionState) {
        switch state {
        case .scanning:
            coreScale = 1.0
            syncProgress = 0.0
            showGreetingBubble = false
            startRadarPingTimer()
            
        case .connecting, .discovering:
            stopRadarPingTimer()
            mediumHaptic.impactOccurred()
            SciFiAudioSynth.shared.playLockSnap()
            
            // Strong gravitational spring compression
            withAnimation(.spring(response: 0.42, dampingFraction: 0.48, blendDuration: 0)) {
                coreScale = 1.22
            }
            
            // Release spring after latch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    coreScale = 1.0
                }
            }
            
        case .handshaking:
            stopRadarPingTimer()
            startHandshakeStepSimulation()
            
        case .ready:
            stopRadarPingTimer()
            handshakeTimer?.invalidate()
            handshakeTimer = nil
            syncProgress = 1.0
            
            heavyHaptic.impactOccurred()
            SciFiAudioSynth.shared.playStartupChirp()
            
            // Trigger Climax Shockwave Shockwave Ripple
            successBurstScale = 0.0
            successBurstOpacity = 1.0
            withAnimation(.easeOut(duration: 1.2)) {
                successBurstScale = 4.5
                successBurstOpacity = 0.0
            }
            
            // Dramatic awakening flash
            withAnimation(.easeOut(duration: 0.45)) {
                showRadialFlash = true
                coreScale = 1.35
            }
            
            // Display character dialog greeting
            startTypewriterGreeting()
            
            // Settle core down and dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                    coreScale = 1.0
                }
            }
            
            // Auto dismiss onboarding and open Face Mode after a beautiful pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) {
                onDismiss()
                dismiss()
            }
            
        case .disconnected:
            coreScale = 1.0
            syncProgress = 0.0
            showGreetingBubble = false
            startRadarPingTimer()
            
        case .reconnecting(_):
            break
        }
    }
    
    // --- Timers & Simulation Drivers ---
    
    private func populateStars() {
        var tempStars: [Star] = []
        for _ in 0..<45 {
            let x = CGFloat.random(in: 0...1)
            let y = CGFloat.random(in: 0...1)
            let size = CGFloat.random(in: 1.2...3.6)
            let speed = Double.random(in: 0.04...0.18)
            let baseOpacity = Double.random(in: 0.25...0.85)
            tempStars.append(Star(x: x, y: y, size: size, speed: speed, baseOpacity: baseOpacity))
        }
        self.stars = tempStars
    }
    
    private func startRadarPingTimer() {
        stopRadarPingTimer()
        SciFiAudioSynth.shared.playRadarPing()
        
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            SciFiAudioSynth.shared.playRadarPing()
            withAnimation(.easeInOut(duration: 0.8)) {
                coreScale = 1.08
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    coreScale = 1.0
                }
            }
        }
    }
    
    private func stopRadarPingTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func startHandshakeStepSimulation() {
        handshakeTimer?.invalidate()
        syncProgress = 0.0
        handshakeStep = 0
        
        let totalSteps = 10
        handshakeTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { timer in
            guard self.session.state == .handshaking else {
                timer.invalidate()
                self.handshakeTimer = nil
                return
            }
            
            handshakeStep += 1
            withAnimation(.easeInOut(duration: 0.28)) {
                syncProgress = CGFloat(handshakeStep) / CGFloat(totalSteps)
            }
            
            // Play progressive rising pentatonic pitch
            SciFiAudioSynth.shared.playNeuralSyncPitch(step: handshakeStep - 1, totalSteps: totalSteps)
            
            // Trigger synchronized physical haptic vibration
            let hapticIntensity = Float(0.25 + Double(handshakeStep) * 0.065)
            lightHaptic.impactOccurred(intensity: CGFloat(hapticIntensity))
            
            if handshakeStep >= totalSteps {
                timer.invalidate()
                self.handshakeTimer = nil
            }
        }
    }
    
    private func startTypewriterGreeting() {
        typewriterText = ""
        showGreetingBubble = true
        let fullText = "Hello, Human! Looi is fully awake! Let's explore the galaxy of emotions together! ✨"
        var idx = 0
        
        Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { timer in
            guard idx < fullText.count else {
                timer.invalidate()
                return
            }
            let charIndex = fullText.index(fullText.startIndex, offsetBy: idx)
            typewriterText.append(fullText[charIndex])
            idx += 1
        }
    }
    
    // --- Helper Getters ---
    
    private var coreGlowColor: Color {
        switch session.state {
        case .scanning, .disconnected:
            return .cyan.opacity(0.35)
        case .connecting, .discovering:
            return .yellow.opacity(0.4)
        case .handshaking:
            return .mint.opacity(0.45)
        case .ready:
            return .orange.opacity(0.5)
        case .reconnecting(_):
            return .red.opacity(0.35)
        }
    }
    
    private var hudTitle: String {
        switch session.state {
        case .disconnected:
            return "意识断开"
        case .scanning:
            return "深空呼唤..."
        case .connecting, .discovering:
            return "引力锁定"
        case .handshaking:
            return "神经同步"
        case .ready:
            return "生命激活！"
        case .reconnecting(let attempt):
            return "正在重连 (\(attempt))..."
        }
    }
    
    private var hudSubtitle: String {
        switch session.state {
        case .disconnected:
            return "寻找 Looi 信号源，请将小身体靠拢"
        case .scanning:
            return "正在发射意识电磁波，探寻附近的 Looi 机器人基座..."
        case .connecting, .discovering:
            return "成功捕获底座物理特征，正在锁定生命连接信道..."
        case .handshaking:
            return "正在同步感官缓冲区，注入情感控制矩阵，建立数字脑波通道..."
        case .ready:
            return "唤醒成功！情感底座与灵性面部完成首次交融。Looi，向世界问好！"
        case .reconnecting:
            return "遇到电磁风暴，正在拼命重连到原有的身体底座..."
        }
    }
    
    private var sysStateStr: String {
        switch session.state {
        case .disconnected:
            return "ECHO_PING_LOST"
        case .scanning:
            return "SCANNING_PULSE"
        case .connecting, .discovering:
            return "CHANNEL_LATCHED"
        case .handshaking:
            return "ECDH_COMPUTING"
        case .ready:
            return "SOUL_SYNCHRONIZED"
        case .reconnecting(_):
            return "RECONNECT_ATTEMPT"
        }
    }
}

// --- SUBVIEWS ---

/// Programmatic Digital Blinking LED Face View
struct BlinkingLEDFaceView: View {
    @State private var isBlinking = false
    @State private var breatheAmount = 1.0
    
    var body: some View {
        VStack(spacing: 8) {
            // Animated breathing and blinking eyes
            HStack(spacing: 24) {
                // Left eye capsule
                Capsule()
                    .fill(Color.orange)
                    .frame(width: 8, height: isBlinking ? 1.5 : 24)
                    .scaleEffect(y: breatheAmount, anchor: .center)
                
                // Right eye capsule
                Capsule()
                    .fill(Color.orange)
                    .frame(width: 8, height: isBlinking ? 1.5 : 24)
                    .scaleEffect(y: breatheAmount, anchor: .center)
            }
            .frame(height: 28)
            
            // Little curved electronic smile
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 18, y: 0), control: CGPoint(x: 9, y: 6))
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 18, height: 6)
            .padding(.top, 4)
        }
        .shadow(color: .orange.opacity(0.65), radius: 6)
        .onAppear {
            // Breathing motion
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breatheAmount = 1.12
            }
            
            // Randomized blinking loop
            Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.08)) {
                    isBlinking = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeInOut(duration: 0.08)) {
                        isBlinking = false
                    }
                }
            }
        }
    }
}
