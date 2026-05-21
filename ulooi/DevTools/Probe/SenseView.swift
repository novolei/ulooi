import LooiKit
import SwiftUI

/// DevTools Sense tab — shows live SensorController data from FED5 (sensors)
/// and FED9 (telemetry) streams decoded by LooiKit.
///
/// # M1 deliberate limitation
/// The former "subscribe to arbitrary notify-able characteristics" UI is NOT
/// available because LooiKit Session does not expose raw CBCharacteristic objects.
/// FED5 + FED9 subscriptions are established automatically by the HandshakeRunner
/// during session.connect(to:) and decoded by SensorController.
///
/// What you see here is the decoded output. For lower-level raw bytes, check the
/// Logs tab (LooiKit logs FED5/FED9 packets at debug level via OSLog).
///
/// TODO (M2): If raw subscription control is still needed for hardware debugging,
/// expose a DevToolsTransportInspector that surfaces individual characteristic streams.
struct SenseView: View {
    let session: LooiSession
    let log: ProbeLog

    @State private var annotation: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Live sensor data (FED9 telemetry)") {
                    if !session.state.isReady {
                        Text("Connect first (Scan tab) — sensor streams start after handshake completes.")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Cliff state") {
                            let cs = session.sensor.cliffState
                            Text(cs.isGrounded ? "grounded" : "0x\(String(cs.rawValue, radix: 16, uppercase: true))")
                                .font(.body.monospaced())
                                .foregroundStyle(cs.isGrounded ? .green : .orange)
                        }
                        LabeledContent("IMU (x / y / z)") {
                            let imu = session.sensor.imu
                            Text("\(imu.x) / \(imu.y) / \(imu.z)")
                                .font(.body.monospacedDigit())
                        }
                        if let touch = session.sensor.lastTouchEvent {
                            LabeledContent("Last touch") {
                                Text("raw=0x\(String(touch.raw, radix: 16, uppercase: true))")
                                    .font(.body.monospaced())
                            }
                        } else {
                            LabeledContent("Last touch", value: "none yet")
                        }
                    }
                }

                Section("Battery (FED8 poll)") {
                    if let pct = session.sensor.batteryPercent {
                        LabeledContent("Battery", value: "\(pct)%")
                        LabeledContent("Poll count", value: "\(session.sensor.batteryPollCount)")
                    } else {
                        Text("Battery not yet read (polls every 4s once connected).")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Annotate event") {
                    TextField("e.g. 'I touched the head now'", text: $annotation)
                    Button("Mark in log") {
                        DevLog.event("== EVENT == \(annotation)", channel: DevLog.ui)
                        annotation = ""
                    }
                    .disabled(annotation.isEmpty)
                }

                Section {
                    Text("[Raw characteristic subscription (arbitrary notify-able chars) is not exposed by LooiKit Session API. FED5 + FED9 are automatically subscribed during handshake and decoded above. See Logs tab for raw OSLog output.]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Raw characteristic subscribe")
                }
            }
            .navigationTitle("Sense")
        }
    }
}

#Preview {
    SenseView(session: LooiBootstrap.shared.session, log: ProbeLog.shared)
}
