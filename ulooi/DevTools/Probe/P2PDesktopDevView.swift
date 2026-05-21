import LooiKit
import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QRCodeView

struct QRCodeView: View {
    let urlString: String
    
    var body: some View {
        if let image = generateQRCode(from: urlString) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 180)
                .padding(8)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        } else {
            VStack {
                ProgressView()
                Text("Generating QR Code...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180, height: 180)
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - P2PDesktopDevView

struct P2PDesktopDevView: View {
    @State private var simulator = PairingSimulator.shared
    
    var body: some View {
        NavigationStack {
            List {
                Section("Simulator Configuration") {
                    Toggle("Enable Desktop Simulator Mode", isOn: Binding(
                        get: { TransportManager.shared.isSimulatorMode },
                        set: { TransportManager.shared.isSimulatorMode = $0 }
                    ))
                    
                    if TransportManager.shared.isSimulatorMode {
                        LabeledContent("Connection State", value: TransportManager.shared.connectionState.rawValue)
                        
                        if let rtt = TransportManager.shared.roundTripTimeMs {
                            LabeledContent("RTT Latency", value: String(format: "%.1f ms", rtt))
                        }
                    }
                }
                
                if TransportManager.shared.isSimulatorMode {
                    Section("Pairing QR Code & Identity") {
                        VStack(alignment: .center, spacing: 12) {
                            QRCodeView(urlString: simulator.pairingURI)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            
                            Button {
                                simulator.resetKeys()
                            } label: {
                                Label("Rotate Simulator Identity Keys", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if !simulator.computedVerificationCode.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Handshake Verification Code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(simulator.computedVerificationCode)
                                    .font(.system(.title, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
                    Section("Simulate Inbound Desktop Commands") {
                        if !simulator.activeSession {
                            Text("Please complete the pairing process via the Scanner to activate simulation controls.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Looi Interactive Face States")
                                    .font(.headline)
                                
                                HStack(spacing: 8) {
                                    Button("Thinking") { simulateAgentState("thinking") }
                                        .buttonStyle(.bordered)
                                        .tint(.cyan)
                                    
                                    Button("Speaking") { simulateAgentState("speaking") }
                                        .buttonStyle(.bordered)
                                        .tint(.orange)
                                    
                                    Button("Listening") { simulateAgentState("listening") }
                                        .buttonStyle(.bordered)
                                        .tint(.mint)
                                    
                                    Button("Idle") { simulateAgentState("idle") }
                                        .buttonStyle(.bordered)
                                        .tint(.secondary)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Motor & Actuation Controls")
                                    .font(.headline)
                                
                                HStack(spacing: 12) {
                                    Button("Forward") { simulateMotion(speed: 0.5, turn: 0.0) }
                                        .buttonStyle(.bordered)
                                    Button("Backward") { simulateMotion(speed: -0.5, turn: 0.0) }
                                        .buttonStyle(.bordered)
                                    Button("Stop") { simulateMotion(speed: 0.0, turn: 0.0) }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                }
                                .controlSize(.small)
                                
                                HStack(spacing: 12) {
                                    Button("Pitch UP") { simulateHeadPitch(10) }
                                        .buttonStyle(.bordered)
                                    Button("Pitch DOWN") { simulateHeadPitch(-10) }
                                        .buttonStyle(.bordered)
                                    Button("Rainbow Light") { simulateLightRainbow() }
                                        .buttonStyle(.bordered)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Physical Mode Active", systemImage: "cpu.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            
                            Text("The application is configured to scan for real local UCLAW Desktop servers running on the network via Bonjour.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("P2P Desktop")
        }
    }
    
    // --- Helper Simulated Dispatchers ---
    
    private func simulateAgentState(_ state: String) {
        let agentState = AgentState(state: state, contextSummary: "Manual debug override")
        let envelope = WireEnvelope(
            src: "uclaw-desktop-simulator",
            kind: "agent.state",
            payload: .agentState(agentState)
        )
        simulator.triggerMockCommand(envelope)
    }
    
    private func simulateMotion(speed: Double, turn: Double) {
        let motionCmd = ActuationMotionCmd(speed: speed, turn: turn)
        let envelope = WireEnvelope(
            src: "uclaw-desktop-simulator",
            kind: "actuation.motion_cmd",
            payload: .actuationMotionCmd(motionCmd)
        )
        simulator.triggerMockCommand(envelope)
    }
    
    private func simulateHeadPitch(_ pitch: Int) {
        let headCmd = ActuationHeadCmd(pitch: pitch)
        let envelope = WireEnvelope(
            src: "uclaw-desktop-simulator",
            kind: "actuation.head_cmd",
            payload: .actuationHeadCmd(headCmd)
        )
        simulator.triggerMockCommand(envelope)
    }
    
    private func simulateLightRainbow() {
        let lightCmd = ActuationLightCmd(mode: "rainbow", rgb: [255, 0, 255], durationMs: 3000)
        let envelope = WireEnvelope(
            src: "uclaw-desktop-simulator",
            kind: "actuation.light_cmd",
            payload: .actuationLightCmd(lightCmd)
        )
        simulator.triggerMockCommand(envelope)
    }
}

#Preview {
    P2PDesktopDevView()
}
