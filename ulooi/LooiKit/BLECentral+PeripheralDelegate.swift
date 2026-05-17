import CoreBluetooth
import Foundation

extension BLECentral: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let msg = error.localizedDescription
            Task { @MainActor in DevLog.error("discoverServices: \(msg)") }
            return
        }
        let services = peripheral.services ?? []
        Task { @MainActor in
            self.discoveredServices = services
            DevLog.event("services: \(services.count)")
            for s in services {
                DevLog.event("  service \(s.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            let msg = error.localizedDescription
            let sid = service.uuid.uuidString
            Task { @MainActor in DevLog.error("discoverChars[\(sid)]: \(msg)") }
            return
        }
        let chars = service.characteristics ?? []
        let sid = service.uuid.uuidString
        Task { @MainActor in
            DevLog.event("  \(chars.count) chars for service \(sid)")
            for c in chars {
                let props = CharacteristicProperties(rawValue: c.properties.rawValue)
                DevLog.event("    char \(c.uuid.uuidString)  props=[\(props.description)]")
            }
            // Trigger Observable update by re-assigning (services list reflects new chars)
            self.discoveredServices = peripheral.services ?? []
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let msg = error.localizedDescription
            Task { @MainActor in DevLog.error("read \(characteristic.uuid): \(msg)") }
            return
        }
        guard let value = characteristic.value else { return }
        let label = characteristic.uuid.uuidString
        Task { @MainActor in
            DevLog.bytes("notify←\(label)", value)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let msg = error.localizedDescription
            let cid = characteristic.uuid.uuidString
            Task { @MainActor in DevLog.error("write \(cid) failed: \(msg)") }
        }
    }
}
