import CoreBluetooth
import SwiftUI

struct ScanView: View {
    // Plain `let` — no `$central.xxx` binding usage; @Observable read-tracking
    // via property access in body is sufficient.
    let central: BLECentral
    let log: ProbeLog

    @State private var serviceFilterText: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("BLE state") {
                    HStack {
                        Text(central.state.rawValue.capitalized)
                            .foregroundStyle(central.state == .poweredOn ? .green : .secondary)
                        Spacer()
                        if central.isScanning {
                            ProgressView()
                        }
                    }
                }

                Section("Filter (optional, comma-separated 16-bit or full UUIDs)") {
                    TextField("e.g. FFE0,180A or full UUID", text: $serviceFilterText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    HStack {
                        Button(central.isScanning ? "Stop Scan" : "Start Scan") {
                            DevLog.event(
                                "ScanView: \(central.isScanning ? "Stop" : "Start") Scan tapped " +
                                "(state=\(central.state.rawValue), isScanning=\(central.isScanning))",
                                channel: DevLog.ui
                            )
                            if central.isScanning {
                                central.stopScan()
                            } else {
                                central.startScan(serviceFilter: parseFilter())
                            }
                        }
                        // Explicit buttonStyle is REQUIRED here. Without it, SwiftUI
                        // treats a multi-Button HStack inside a Form Section row as a
                        // single tap target — tapping anywhere on the row fires BOTH
                        // Buttons in source order (Start Scan → Clear results), which
                        // immediately cancels the scan before any didDiscover callback
                        // can fire. Smoking gun: console showed
                        //   Start Scan tapped → scan: start → Clear results tapped →
                        //   scan: stop (found 0)
                        // all triggered by a single tap. See [[feedback-swiftui-form-row-buttons]].
                        .buttonStyle(.borderedProminent)
                        .disabled(central.state != .poweredOn)
                        Spacer()
                        Button("Clear results", role: .destructive) {
                            DevLog.event("ScanView: Clear results tapped", channel: DevLog.ui)
                            central.stopScan()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("Discovered (\(central.discoveries.count))") {
                    let items = central.discoveries.values.sorted {
                        $0.rssi > $1.rssi
                    }
                    if items.isEmpty {
                        Text("No peripherals yet. Tap Start Scan.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { d in
                            DiscoveryRow(discovery: d, central: central, log: log)
                        }
                    }
                }
            }
            .navigationTitle("Scan")
        }
    }

    private func parseFilter() -> [CBUUID]? {
        let trimmed = serviceFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let uuids = parts.compactMap { p -> CBUUID? in
            // accept 4-char (16-bit) or full 32-char UUID
            if p.count == 4 { return CBUUID(string: String(p)) }
            if p.count >= 32 { return CBUUID(string: String(p)) }
            log.warn("scan filter: skipped \(p)")
            return nil
        }
        return uuids.isEmpty ? nil : uuids
    }
}

private struct DiscoveryRow: View {
    let discovery: BLECentral.Discovery
    let central: BLECentral
    let log: ProbeLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(discovery.name)
                    .font(.headline)
                Spacer()
                Text("\(discovery.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(rssiColor(discovery.rssi))
            }
            Text(discovery.id.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if !discovery.advertisedServices.isEmpty {
                Text("services: \(discovery.advertisedServices.map { $0.uuidString }.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let mfg = discovery.manufacturerData {
                Text("mfg: \(mfg.hexEncoded)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Button("Connect") {
                    central.connect(discovery.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi > -60 { return .green }
        if rssi > -80 { return .orange }
        return .red
    }
}

#Preview {
    ScanView(central: BLECentral.shared, log: ProbeLog.shared)
}
