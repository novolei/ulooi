import CoreBluetooth
import Foundation

extension BLECentral: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = BLECentral.translate(central.state)
        Task { @MainActor in
            self.state = newState
            self.log.info("BLE state → \(newState.rawValue)")
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
            self.discoveries[id] = Discovery(
                id: id,
                name: name,
                rssi: rssiInt,
                advertisedServices: services,
                manufacturerData: mfg,
                lastSeen: Date()
            )
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let pid = peripheral.identifier
        Task { @MainActor in
            self.log.info("connected: \(pid)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown"
        let pid = peripheral.identifier
        Task { @MainActor in
            self.log.error("connect failed: \(pid) — \(msg)")
            self.connectedPeripheral = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let pid = peripheral.identifier
        let msg = error?.localizedDescription ?? "(clean)"
        Task { @MainActor in
            self.log.info("disconnected: \(pid) — \(msg)")
            self.connectedPeripheral = nil
            self.discoveredServices.removeAll()
        }
    }
}
