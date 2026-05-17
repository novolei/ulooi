import CoreBluetooth
import SwiftUI

struct InspectView: View {
    let central: BLECentral
    let log: ProbeLog

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    if let p = central.connectedPeripheral {
                        VStack(alignment: .leading) {
                            Text(p.name ?? "(unnamed)")
                                .font(.headline)
                            Text(p.identifier.uuidString)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text("state: \(stateLabel(p.state))")
                                .font(.caption)
                        }
                        HStack {
                            Button("Discover all services") {
                                central.discoverAllServices()
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            Button("Disconnect", role: .destructive) {
                                central.disconnect()
                            }
                        }
                    } else {
                        Text("Not connected. Go to Scan tab.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !central.discoveredServices.isEmpty {
                    Section("GATT topology (\(central.discoveredServices.count) services)") {
                        ForEach(central.discoveredServices, id: \.uuid) { service in
                            ServiceRow(service: service, central: central)
                        }
                    }

                    Section {
                        Button("Copy topology as JSON") {
                            let json = serializeTopology(central.discoveredServices)
                            #if canImport(UIKit)
                            UIPasteboard.general.string = json
                            #endif
                            log.info("topology copied to clipboard (\(json.count) chars)")
                        }
                    }
                }
            }
            .navigationTitle("Inspect")
        }
    }

    private func stateLabel(_ state: CBPeripheralState) -> String {
        switch state {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

    private func serializeTopology(_ services: [CBService]) -> String {
        var lines: [String] = []
        for s in services {
            lines.append("- service \(s.uuid.uuidString)")
            for c in s.characteristics ?? [] {
                let props = CharacteristicProperties(rawValue: c.properties.rawValue)
                lines.append("  - char \(c.uuid.uuidString)  props=[\(props.description)]")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private struct ServiceRow: View {
    let service: CBService
    let central: BLECentral

    var body: some View {
        DisclosureGroup {
            ForEach(service.characteristics ?? [], id: \.uuid) { char in
                CharacteristicRow(characteristic: char, central: central)
            }
        } label: {
            VStack(alignment: .leading) {
                Text(service.uuid.uuidString)
                    .font(.subheadline.monospaced())
                Text("\(service.characteristics?.count ?? 0) characteristics")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CharacteristicRow: View {
    let characteristic: CBCharacteristic
    let central: BLECentral

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(characteristic.uuid.uuidString)
                .font(.caption.monospaced())
            let props = CharacteristicProperties(rawValue: characteristic.properties.rawValue)
            Text(props.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                if props.contains(.read) {
                    Button("Read") {
                        central.connectedPeripheral?.readValue(for: characteristic)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
                if props.contains(.notify) {
                    Button(characteristic.isNotifying ? "Unsubscribe" : "Subscribe") {
                        if characteristic.isNotifying {
                            central.unsubscribe(from: characteristic)
                        } else {
                            central.subscribe(to: characteristic)
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    InspectView(central: BLECentral.shared, log: ProbeLog.shared)
}
