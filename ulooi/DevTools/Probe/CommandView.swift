import CoreBluetooth
import SwiftUI

struct CommandView: View {
    let central: BLECentral
    let log: ProbeLog

    @State private var hexInput: String = ""
    @State private var manualTargetID: CBUUID?
    @State private var useWriteWithoutResponse: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                motionSection
                presetSection
                manualSection
            }
            .navigationTitle("Send Command")
        }
        .onAppear {
            if manualTargetID == nil, let first = writableCharacteristics.first {
                manualTargetID = first.uuid
            }
        }
    }

    // MARK: - Motion (heartbeat-aware)

    private var motionSection: some View {
        Section {
            ForEach(MotionPreset.all) { preset in
                motionButton(for: preset)
            }
        } header: {
            Text("Motion control (heartbeat-aware) — current: \(central.currentMotion.label)")
        } footer: {
            Text("Tapping a motion replaces the heartbeat payload — robot keeps moving until you tap STOP. Auto-resets to STOP on disconnect.")
                .font(.caption2)
        }
    }

    /// Extracted to its own helper because inlining `Button { ... }
    /// .buttonStyle(cond ? .borderedProminent : .bordered)` triggers
    /// `The compiler is unable to type-check this expression in reasonable
    /// time`. The ternary returns two different concrete style types
    /// (`BorderedProminentButtonStyle` vs `BorderedButtonStyle`) and the
    /// type inference cascade through ViewBuilder blows up. Splitting the
    /// branches with an explicit if/else and `@ViewBuilder` keeps each path's
    /// type concrete and the compiler happy.
    @ViewBuilder
    private func motionButton(for preset: MotionPreset) -> some View {
        // Disable motion controls when not connected — prevents the
        // confusing case where the user taps Forward without a live
        // connection (currentMotion mutates but no heartbeat is running
        // to deliver it), and also blocks accidentally arming a non-STOP
        // motion that would then auto-execute the moment an auto-reconnect
        // completes the INIT handshake.
        let connected = central.connectedPeripheral != nil

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
        central.currentMotion = MotionState(label: preset.label, data: preset.bytes)
        DevLog.event("motion → \(preset.label) (heartbeat sends each 30ms)", channel: DevLog.ui)
    }

    // MARK: - Presets

    private var presetSection: some View {
        Section {
            ForEach(LooiCommand.allPresets) { preset in
                PresetRow(preset: preset,
                          isAvailable: characteristic(for: preset.characteristic) != nil) {
                    sendPreset(preset)
                }
            }
        } header: {
            Text("Looi presets — hit INIT 1/2 then INIT 2/2 first")
        } footer: {
            Text("✅ verified  ⚠️ unverified  ❓ experimental\nA preset is greyed out if its target characteristic hasn't been discovered yet (Inspect tab → Discover all services).")
                .font(.caption2)
        }
    }

    // MARK: - Manual

    private var manualSection: some View {
        Section("Manual write") {
            if writableCharacteristics.isEmpty {
                Text("Connect + discover services first.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Characteristic", selection: $manualTargetID) {
                    ForEach(writableCharacteristics, id: \.uuid) { c in
                        Text(displayName(for: c.uuid)).tag(Optional(c.uuid))
                    }
                }
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
                .disabled(manualTarget == nil || hexInput.isEmpty)
            }
        }
    }

    // MARK: - Logic

    private var writableCharacteristics: [CBCharacteristic] {
        central.discoveredServices.flatMap { $0.characteristics ?? [] }.filter {
            let props = CharacteristicProperties(rawValue: $0.properties.rawValue)
            return props.contains(.write) || props.contains(.writeNoResp)
        }
    }

    private var manualTarget: CBCharacteristic? {
        guard let id = manualTargetID else { return nil }
        return writableCharacteristics.first { $0.uuid == id }
    }

    private func characteristic(for uuid: CBUUID) -> CBCharacteristic? {
        central.discoveredServices
            .flatMap { $0.characteristics ?? [] }
            .first { $0.uuid == uuid }
    }

    private func sendHex() {
        guard let char = manualTarget else { return }
        guard let data = Data(hexString: hexInput) else {
            log.error("invalid hex: \(hexInput)")
            return
        }
        let type: CBCharacteristicWriteType = useWriteWithoutResponse ? .withoutResponse : .withResponse
        central.write(data, to: char, type: type)
    }

    private func sendPreset(_ preset: LooiCommand.Preset) {
        guard let char = characteristic(for: preset.characteristic) else {
            log.warn("preset '\(preset.label)' — target char \(preset.characteristic.uuidString) not discovered")
            return
        }
        log.info("preset: \(preset.label)  src=\(preset.source)  status=\(preset.status.rawValue)")
        central.write(preset.bytes, to: char)
    }

    private func displayName(for uuid: CBUUID) -> String {
        // Map known Looi UUIDs to friendlier labels.
        switch uuid {
        case LooiProtocol.Char.movement:    return "FED0 (movement)"
        case LooiProtocol.Char.head:        return "FED1 (head)"
        case LooiProtocol.Char.light:       return "FED2 (light)"
        case LooiProtocol.Char.handshake:   return "FEDA (handshake)"
        case LooiProtocol.Char.richCommand: return "FE00 (rich/17-byte)"
        case LooiProtocol.Char.motorBoost:  return "FF02 (motor boost)"
        default:                            return uuid.uuidString
        }
    }
}

// MARK: - Row

private struct PresetRow: View {
    let preset: LooiCommand.Preset
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(preset.status.rawValue)
                    Text(preset.label)
                        .font(.body)
                        .foregroundStyle(isAvailable ? Color.primary : Color.secondary)
                }
                Text("→ \(shortName(preset.characteristic))   bytes: \(preset.bytes.hexEncoded)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("src: \(preset.source)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let note = preset.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .disabled(!isAvailable)
    }

    private func shortName(_ uuid: CBUUID) -> String {
        let s = uuid.uuidString
        // For 16-bit "0000XXXX-..." pull the X part for a compact label
        if s.count >= 8 && s.hasPrefix("0000") {
            let idx = s.index(s.startIndex, offsetBy: 4)
            let end = s.index(idx, offsetBy: 4)
            return s[idx..<end].uppercased() + " (" + uuid.uuidString.prefix(8) + ")"
        }
        return s
    }
}

// `Data.init?(hexString:)` and `Data.hexEncoded` live in `Shared/DataHexCodec.swift`.

#Preview {
    CommandView(central: BLECentral.shared, log: ProbeLog.shared)
}
