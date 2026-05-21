import LooiKit
import SwiftUI

/// DevTools Inspect tab — shows the current session state and connected
/// peripheral identity.
///
/// # M1 deliberate limitation
/// Raw GATT topology inspection (findCharacteristic / write / subscribe on raw
/// CBCharacteristic objects) is NOT exposed by the LooiKit Session API by design
/// — all BLE I/O goes through the four Controllers. The former Discover / Read /
/// Subscribe / Copy-topology buttons are therefore not available in this tab.
///
/// TODO (M2): If raw topology inspection is still needed for hardware debugging,
/// expose a `DevToolsTransportInspector` that wraps CoreBluetoothTransport and
/// surfaces the discovered services after `discoverServicesAndCharacteristics`.
struct InspectView: View {
    let session: LooiSession
    let log: ProbeLog

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("State", value: session.state.description)
                    if let p = session.currentPeripheral {
                        LabeledContent("Name", value: p.name)
                        LabeledContent("ID", value: p.id.uuidString)
                            .font(.caption2.monospaced())
                        HStack {
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                session.disconnect()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Text("Not connected. Go to Scan tab.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Controllers") {
                    LabeledContent("Motion", value: session.motion.currentMotion.label)
                    LabeledContent("Heartbeat ticks", value: "\(session.motion.heartbeatTicks)")
                    LabeledContent("Battery polls", value: "\(session.sensor.batteryPollCount)")
                    if let pct = session.sensor.batteryPercent {
                        LabeledContent("Battery", value: "\(pct)%")
                    }
                    LabeledContent("Cliff state") {
                        let cs = session.sensor.cliffState
                        Text(cs.isGrounded ? "grounded" : "0x\(String(cs.rawValue, radix: 16, uppercase: true))")
                            .foregroundStyle(cs.isGrounded ? .green : .orange)
                    }
                    LabeledContent("IMU x/y/z", value: {
                        let imu = session.sensor.imu
                        return "\(imu.x) / \(imu.y) / \(imu.z)"
                    }())
                }

                Section {
                    Text("[deferred — raw GATT topology inspection not exposed by LooiKit Session API. All BLE I/O goes through MotionController / HeadController / LightController / SensorController. Use the Send tab for preset commands.]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Raw GATT topology")
                }
            }
            .navigationTitle("Inspect")
        }
    }
}

#Preview {
    InspectView(session: LooiBootstrap.shared.session, log: ProbeLog.shared)
}
