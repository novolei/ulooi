import LooiKit
import SwiftUI

struct CommandView: View {
    let session: LooiSession
    let log: ProbeLog

    var body: some View {
        NavigationStack {
            Form {
                motionSection
                headSection
                lightSection
                manualWriteStubSection
            }
            .navigationTitle("Send Command")
        }
    }

    // MARK: - Motion (via MotionController.setMotion)

    private var motionSection: some View {
        Section {
            ForEach(MotionPreset.all) { preset in
                motionButton(for: preset)
            }
        } header: {
            Text("Motion (via MotionController) — current: \(session.motion.currentMotion.label)")
        } footer: {
            Text("Tapping a motion routes through MotionController.setMotion, which updates the 30ms heartbeat payload. STOP bypasses the cliff check. Auto-resets to STOP on disconnect.")
                .font(.caption2)
        }
    }

    /// Extracted to a @ViewBuilder helper to avoid the Swift 6 type-checker
    /// timeout from inline ternary on different concrete button style types.
    /// See [[feedback-swiftui-conditional-modifiers]].
    @ViewBuilder
    private func motionButton(for preset: MotionPreset) -> some View {
        let connected = session.currentPeripheral != nil
        if preset.label == "STOP" {
            Button(preset.label) { applyMotion(preset) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!connected)
        } else {
            Button(preset.label) { applyMotion(preset) }
                .buttonStyle(.bordered)
                .disabled(!connected)
        }
    }

    private func applyMotion(_ preset: MotionPreset) {
        let target = MotionState(label: preset.label, data: preset.bytes)
        do {
            try session.motion.setMotion(target)
            DevLog.event(
                "motion → \(preset.label) (bytes: \(preset.bytes.hexEncoded), heartbeat picks up on next tick)",
                channel: DevLog.ui
            )
        } catch {
            DevLog.warn("motion setMotion failed: \(error) — cliff blocked?", channel: DevLog.ui)
        }
    }

    // MARK: - Head (via HeadController)

    private var headSection: some View {
        Section {
            let connected = session.currentPeripheral != nil
            HStack {
                Button("Look Up") {
                    Task { try? await session.head.lookUp() }
                    DevLog.event("head: lookUp", channel: DevLog.ui)
                }
                .buttonStyle(.bordered)
                .disabled(!connected)
                Spacer()
                Button("Look Down") {
                    Task { try? await session.head.lookDown() }
                    DevLog.event("head: lookDown step (+0x20 from current)", channel: DevLog.ui)
                }
                .buttonStyle(.bordered)
                .disabled(!connected)
                Spacer()
                Button("Center") {
                    Task { try? await session.head.center() }
                    DevLog.event("head: center", channel: DevLog.ui)
                }
                .buttonStyle(.bordered)
                .disabled(!connected)
            }
        } header: {
            Text("Head (via HeadController — FED1)")
        }
    }

    // MARK: - Light (via LightController)

    private var lightSection: some View {
        Section {
            let connected = session.currentPeripheral != nil
            HStack {
                Button("Full") {
                    Task { try? await session.light.set(brightness: 1.0) }
                    DevLog.event("light: full (1.0 -> 0x7F)", channel: DevLog.ui)
                }
                .buttonStyle(.bordered)
                .disabled(!connected)
                Spacer()
                Button("Half") {
                    Task { try? await session.light.set(brightness: 0.5) }
                    DevLog.event("light: half (0.5)", channel: DevLog.ui)
                }
                .buttonStyle(.bordered)
                .disabled(!connected)
                Spacer()
                Button("Off") {
                    Task { try? await session.light.off() }
                    DevLog.event("light: off", channel: DevLog.ui)
                }
                .buttonStyle(.bordered)
                .disabled(!connected)
            }
        } header: {
            Text("Light (via LightController — FED2)")
        }
    }

    // MARK: - Manual write stub

    private var manualWriteStubSection: some View {
        Section {
            Text("[use Controllers — raw write to arbitrary characteristics is not exposed by LooiKit Session API. Use Motion / Head / Light sections above for direct command sending.]")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Manual raw write")
        }
    }
}

// `Data.hexEncoded` lives in `Shared/DataHexCodec.swift`.

#Preview {
    CommandView(session: LooiBootstrap.shared.session, log: ProbeLog.shared)
}
