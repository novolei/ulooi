import LooiKit
import SwiftUI

/// Green status banner shown when the session has a connected peripheral.
/// Visible at the top of the DevTools surface across all tabs so the user
/// can always tell at a glance whether we have an active BLE session.
///
/// Hidden when `session.currentPeripheral` is nil (i.e. not yet connected).
struct ConnectionBanner: View {
    let session: LooiSession

    var body: some View {
        if let peripheral = session.currentPeripheral {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected: \(peripheral.name)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label("\(session.motion.heartbeatTicks)", systemImage: "heart.fill")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.pink)
                        Label("\(session.sensor.batteryPollCount)", systemImage: "battery.100")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let pct = session.sensor.batteryPercent {
                            Label("\(pct)%", systemImage: "bolt.fill")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.green)
                        }
                        // Current motion target — orange + bold when robot is
                        // actively moving (anything except STOP) so the user
                        // has an unmissable visual cue that the heartbeat is
                        // pushing a non-idle command.
                        let motionLabel = session.motion.currentMotion.label
                        let isMoving = motionLabel != "STOP"
                        Text("→ \(motionLabel)")
                            .font(.caption2.weight(isMoving ? .heavy : .regular))
                            .foregroundStyle(isMoving ? .orange : .secondary)
                    }
                }

                Spacer()

                Button("Disconnect", role: .destructive) {
                    session.disconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.green.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.green.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 8)
        }
    }
}

#Preview {
    ConnectionBanner(session: LooiBootstrap.shared.session)
}
