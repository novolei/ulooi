import CoreBluetooth
import Foundation
import Observation

/// Minimal CoreBluetooth wrapper for M0.5 probe.
/// M1 will lift this into Packages/LooiKit and reshape into the public LooiDevice abstraction.
@MainActor
@Observable
final class BLECentral: NSObject {
    static let shared = BLECentral()

    enum State: String {
        case unknown, unsupported, unauthorized, poweredOff, poweredOn
    }

    struct Discovery: Identifiable, Hashable {
        let id: UUID
        var name: String
        var rssi: Int
        var advertisedServices: [CBUUID]
        var manufacturerData: Data?
        var lastSeen: Date
    }

    private(set) var state: State = .unknown
    private(set) var discoveries: [UUID: Discovery] = [:]
    private(set) var connectedPeripheral: CBPeripheral?
    private(set) var discoveredServices: [CBService] = []
    private(set) var isScanning: Bool = false

    private var central: CBCentralManager!
    private let log = ProbeLog.shared

    override init() {
        super.init()
        // queue=.main keeps delegate callbacks on the main actor (no thread hop).
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scan

    func startScan(serviceFilter: [CBUUID]? = nil) {
        guard state == .poweredOn else {
            log.warn("startScan: BLE not powered on (state=\(state.rawValue))")
            return
        }
        log.info("scan: start (filter=\(serviceFilter?.map { $0.uuidString }.joined(separator: ",") ?? "any"))")
        discoveries.removeAll()
        isScanning = true
        central.scanForPeripherals(
            withServices: serviceFilter,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        guard isScanning else { return }
        log.info("scan: stop (found \(discoveries.count))")
        central.stopScan()
        isScanning = false
    }

    // MARK: - Connect / Disconnect

    func connect(_ id: UUID) {
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else {
            log.error("connect: peripheral \(id) not retrievable; scan first")
            return
        }
        log.info("connect: \(peripheral.identifier) name=\(peripheral.name ?? "?")")
        peripheral.delegate = self
        connectedPeripheral = peripheral
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        log.info("disconnect: \(p.identifier)")
        central.cancelPeripheralConnection(p)
    }

    // MARK: - GATT discovery

    func discoverAllServices() {
        guard let p = connectedPeripheral, p.state == .connected else {
            log.warn("discoverAllServices: not connected")
            return
        }
        log.info("discoverServices: requesting all")
        discoveredServices.removeAll()
        p.discoverServices(nil)
    }

    // MARK: - Write / Subscribe

    func write(_ data: Data, to characteristic: CBCharacteristic, type: CBCharacteristicWriteType = .withResponse) {
        guard let p = connectedPeripheral else {
            log.warn("write: not connected")
            return
        }
        log.bytes("write→\(characteristic.uuid.uuidString)", data)
        p.writeValue(data, for: characteristic, type: type)
    }

    func subscribe(to characteristic: CBCharacteristic) {
        guard let p = connectedPeripheral else { return }
        log.info("subscribe: \(characteristic.uuid.uuidString)")
        p.setNotifyValue(true, for: characteristic)
    }

    func unsubscribe(from characteristic: CBCharacteristic) {
        guard let p = connectedPeripheral else { return }
        log.info("unsubscribe: \(characteristic.uuid.uuidString)")
        p.setNotifyValue(false, for: characteristic)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentral: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState: State
        switch central.state {
        case .unknown, .resetting: newState = .unknown
        case .unsupported: newState = .unsupported
        case .unauthorized: newState = .unauthorized
        case .poweredOff: newState = .poweredOff
        case .poweredOn: newState = .poweredOn
        @unknown default: newState = .unknown
        }
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

// MARK: - CBPeripheralDelegate

extension BLECentral: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let msg = error.localizedDescription
            Task { @MainActor in self.log.error("discoverServices: \(msg)") }
            return
        }
        let services = peripheral.services ?? []
        Task { @MainActor in
            self.discoveredServices = services
            self.log.info("services: \(services.count)")
            for s in services {
                self.log.info("  service \(s.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: s)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            let msg = error.localizedDescription
            let sid = service.uuid.uuidString
            Task { @MainActor in self.log.error("discoverChars[\(sid)]: \(msg)") }
            return
        }
        let chars = service.characteristics ?? []
        let sid = service.uuid.uuidString
        Task { @MainActor in
            self.log.info("  \(chars.count) chars for service \(sid)")
            for c in chars {
                let props = CharacteristicProperties(rawValue: c.properties.rawValue)
                self.log.info("    char \(c.uuid.uuidString)  props=[\(props.description)]")
            }
            // Trigger Observable update by re-assigning
            self.discoveredServices = peripheral.services ?? []
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let msg = error.localizedDescription
            Task { @MainActor in self.log.error("read \(characteristic.uuid): \(msg)") }
            return
        }
        guard let value = characteristic.value else { return }
        let label = characteristic.uuid.uuidString
        Task { @MainActor in
            self.log.bytes("notify←\(label)", value)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let msg = error.localizedDescription
            let cid = characteristic.uuid.uuidString
            Task { @MainActor in self.log.error("write \(cid) failed: \(msg)") }
        }
    }
}

// MARK: - Helpers

struct CharacteristicProperties: OptionSet, CustomStringConvertible {
    let rawValue: UInt
    static let broadcast = CharacteristicProperties(rawValue: 0x01)
    static let read = CharacteristicProperties(rawValue: 0x02)
    static let writeNoResp = CharacteristicProperties(rawValue: 0x04)
    static let write = CharacteristicProperties(rawValue: 0x08)
    static let notify = CharacteristicProperties(rawValue: 0x10)
    static let indicate = CharacteristicProperties(rawValue: 0x20)
    static let signed = CharacteristicProperties(rawValue: 0x40)
    static let extended = CharacteristicProperties(rawValue: 0x80)

    var description: String {
        var parts: [String] = []
        if contains(.read) { parts.append("read") }
        if contains(.write) { parts.append("write") }
        if contains(.writeNoResp) { parts.append("wnr") }
        if contains(.notify) { parts.append("notify") }
        if contains(.indicate) { parts.append("indicate") }
        if contains(.broadcast) { parts.append("bcast") }
        return parts.joined(separator: "|")
    }
}
