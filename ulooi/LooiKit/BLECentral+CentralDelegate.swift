import CoreBluetooth
import Foundation

extension BLECentral: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = BLECentral.translate(central.state)
        Task { @MainActor in
            self.state = newState
            DevLog.event("BLE state → \(newState.rawValue)")

            // Auto-reconnect to the last paired Looi when BLE comes up.
            // Skip if already connected (avoids race if user manually
            // connected before BLE state callback fires).
            if newState == .poweredOn,
               let savedID = self.pairedPeripheralID,
               self.connectedPeripheral == nil {
                DevLog.event(
                    "auto-reconnect: attempting saved Looi \(savedID.uuidString.prefix(8))",
                    channel: DevLog.ble
                )
                Task { @MainActor in
                    await self.connectAndAutoInitLooi(savedID)
                }
            }
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
            // Name filter: silently drop non-matching peripherals so the
            // discoveries list + console aren't flooded with 20+ devices
            // when we only care about LOOI. Empty filter = no filter.
            let filter = self.nameFilter
            if !filter.isEmpty,
               !name.uppercased().contains(filter.uppercased()) {
                return
            }

            let now = Date()
            let existing = self.discoveries[id]
            let isNew = existing == nil

            // Throttle: with allowDuplicates=true, each peripheral fires 5-10
            // didDiscover callbacks per second. Without throttling, every callback
            // mutates `discoveries`, which triggers SwiftUI to re-render and
            // re-sort the entire list — visually presents as "flashing and
            // jittering". We allow updates only every 300ms per peripheral.
            // RSSI updates lag by at most 300ms, which is fine for "find Looi" UX
            // but keeps the list visually calm.
            let throttleInterval: TimeInterval = 0.3
            if !isNew, let last = existing?.lastSeen,
               now.timeIntervalSince(last) < throttleInterval {
                return
            }

            self.discoveries[id] = Discovery(
                id: id,
                name: name,
                rssi: rssiInt,
                advertisedServices: services,
                manufacturerData: mfg,
                lastSeen: now
            )
            // First sighting of a peripheral — log via DevLog (Xcode console + ProbeLog).
            // Subsequent throttled updates are silent.
            if isNew {
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
            DevLog.event("connected: \(pid)", channel: DevLog.ble)
            // Auto-discover services on connect. Without this, Looi would drop
            // the connection within ~2s waiting for the INIT handshake (which
            // requires service/char discovery first). Discovering all services
            // is also harmless for non-Looi peripherals.
            DevLog.event("auto-discoverServices: starting", channel: DevLog.ble)
            self.discoveredServices.removeAll()
            peripheral.discoverServices(nil)
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
            let hbInfo: String = {
                guard let start = self.heartbeatStartTime, self.heartbeatTicks > 0 else {
                    return " (no heartbeat ticks were sent)"
                }
                let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
                return " (heartbeat: \(self.heartbeatTicks) ticks over \(elapsed)s before disconnect)"
            }()
            DevLog.event("disconnected: \(pid) — \(msg)\(hbInfo) (battery polls: \(self.batteryPolls))")
            self.cancelMotorHeartbeat()  // stop the motor keep-alive loop
            self.cancelBatteryPoll()     // stop the battery poll keep-alive loop
            // Safety: reset motion state. Without this, an auto-reconnect
            // (triggered by saved pairing) would have the heartbeat resume
            // writing whatever motion was last selected — e.g., Forward —
            // and the robot would start moving without user intent.
            self.currentMotion = .stop
            self.connectedPeripheral = nil
            self.discoveredServices.removeAll()
        }
    }
}
