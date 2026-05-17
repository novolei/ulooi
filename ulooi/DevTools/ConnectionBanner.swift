import SwiftUI

/// Green status banner shown when a peripheral is connected. Visible at the
/// top of the DevTools surface across all tabs so the user can always tell
/// at a glance whether we have an active BLE session — independent of the
/// console output.
///
/// Hidden when `central.connectedPeripheral` is nil.
struct ConnectionBanner: View {
    let central: BLECentral

    var body: some View {
        if let peripheral = central.connectedPeripheral {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Connected: \(peripheral.name ?? "Unknown")")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label("\(central.heartbeatTicks)", systemImage: "heart.fill")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.pink)
                        Label("\(central.batteryPolls)", systemImage: "battery.100")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let start = central.heartbeatStartTime {
                            let elapsed = Int(Date().timeIntervalSince(start))
                            Label("\(elapsed)s", systemImage: "clock")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Button("Disconnect", role: .destructive) {
                    central.disconnect()
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
    ConnectionBanner(central: BLECentral.shared)
}
