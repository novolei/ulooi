import CoreBluetooth
import SwiftUI

struct CommandView: View {
    @Bindable var central: BLECentral
    let log: ProbeLog

    @State private var hexInput: String = ""
    @State private var selectedCharacteristicID: CBUUID?
    @State private var useWriteWithoutResponse: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Target characteristic") {
                    writableCharsPicker
                    if writableCharacteristics.isEmpty {
                        Text("Connect + discover services first.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Bytes to send") {
                    TextField("Hex (e.g. 7E A1 03 00 FF)", text: $hexInput, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Toggle("Write without response", isOn: $useWriteWithoutResponse)
                    Button("Send") {
                        sendHex()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCharacteristic == nil || hexInput.isEmpty)
                }

                Section("Reference presets (UNVERIFIED — see LooiCommand.swift)") {
                    ForEach(Array(LooiCommand.allPresets.enumerated()), id: \.offset) { _, preset in
                        Button {
                            sendPreset(preset)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(preset.label)
                                Text("\(preset.source) · \(preset.bytes.hexEncoded)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(selectedCharacteristic == nil)
                    }
                }
            }
            .navigationTitle("Send Command")
        }
        .onAppear {
            if selectedCharacteristicID == nil, let first = writableCharacteristics.first {
                selectedCharacteristicID = first.uuid
            }
        }
    }

    private var writableCharacteristics: [CBCharacteristic] {
        central.discoveredServices.flatMap { $0.characteristics ?? [] }.filter {
            let props = CharacteristicProperties(rawValue: $0.properties.rawValue)
            return props.contains(.write) || props.contains(.writeNoResp)
        }
    }

    private var selectedCharacteristic: CBCharacteristic? {
        guard let id = selectedCharacteristicID else { return nil }
        return writableCharacteristics.first { $0.uuid == id }
    }

    @ViewBuilder
    private var writableCharsPicker: some View {
        if writableCharacteristics.isEmpty {
            EmptyView()
        } else {
            Picker("Characteristic", selection: $selectedCharacteristicID) {
                ForEach(writableCharacteristics, id: \.uuid) { c in
                    Text(c.uuid.uuidString).tag(Optional(c.uuid))
                }
            }
        }
    }

    private func sendHex() {
        guard let char = selectedCharacteristic else { return }
        guard let data = Data(hexString: hexInput) else {
            log.error("invalid hex: \(hexInput)")
            return
        }
        let type: CBCharacteristicWriteType = useWriteWithoutResponse ? .withoutResponse : .withResponse
        central.write(data, to: char, type: type)
    }

    private func sendPreset(_ preset: (label: String, source: String, bytes: Data)) {
        guard let char = selectedCharacteristic else { return }
        log.info("preset: \(preset.label)  src=\(preset.source)")
        central.write(preset.bytes, to: char)
    }
}

extension Data {
    init?(hexString: String) {
        // accept "ab cd ef" or "abcdef" or "ab-cd:ef"
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self.init(bytes)
    }
}

#Preview {
    CommandView(central: BLECentral.shared, log: ProbeLog.shared)
}
