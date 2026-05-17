import CoreBluetooth
import Foundation

extension BLECentral: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = BLECentral.translate(central.state)
        Task { @MainActor in
            self.state = newState
            DevLog.event("BLE state → \(newState.rawValue)")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let rssiInt = RSSI.intValue
        Task { @MainActor in
            let alreadyKnown = self.discoveries[id] != nil
            self.discoveries[id] = Discovery(
                id: id,
                name: name,
                rssi: rssiInt,
                advertisedServices: services,
                manufacturerData: mfg,
                lastSeen: Date()
            )
            // First sighting of a peripheral — log via DevLog (Xcode console + ProbeLog).
            // Subsequent ad packets from the same peripheral are silent to avoid spam
            // (scan can fire 10+ packets/sec per device with allowDuplicates=true).
            if !alreadyKnown {
                let svcDesc = services.isEmpty ? "no-svc-adv" : services.map { $0.uuidString }.joined(separator: ",")
                DevLog.event(
                    "didDiscover: name=\(name) id=\(id.uuidString.prefix(8)) rssi=\(rssiInt) services=[\(svcDesc)]",
                    channel: DevLog.ble
                )
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let pid = peripheral.identifier
        Task { @MainActor in
            DevLog.event("connected: \(pid)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown"
        let pid = peripheral.identifier
        Task { @MainActor in
            DevLog.error("connect failed: \(pid) — \(msg)")
            self.connectedPeripheral = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let pid = peripheral.identifier
        let msg = error?.localizedDescription ?? "(clean)"
        Task { @MainActor in
            DevLog.event("disconnected: \(pid) — \(msg)")
            self.connectedPeripheral = nil
            self.discoveredServices.removeAll()
        }
    }
}
