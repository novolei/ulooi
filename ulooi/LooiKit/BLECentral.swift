import CoreBluetooth
import Foundation
import Observation

/// Minimal CoreBluetooth wrapper for M0.5 probe.
///
/// Public API: scan / connect / disconnect / discover services / write / subscribe.
/// Delegate implementations live in:
/// - `BLECentral+CentralDelegate.swift`   (CBCentralManagerDelegate)
/// - `BLECentral+PeripheralDelegate.swift` (CBPeripheralDelegate)
///
/// M1 will lift the BLE layer into `Packages/LooiKit/` and reshape into the
/// public `LooiDevice` abstraction.
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

    // Visible to delegate extensions in the same module.
    var central: CBCentralManager!
    let log = ProbeLog.shared

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

    // MARK: - State translation (used by central delegate)

    static func translate(_ cb: CBManagerState) -> State {
        switch cb {
        case .unknown, .resetting: return .unknown
        case .unsupported:         return .unsupported
        case .unauthorized:        return .unauthorized
        case .poweredOff:          return .poweredOff
        case .poweredOn:           return .poweredOn
        @unknown default:          return .unknown
        }
    }
}
