#if canImport(CoreBluetooth) && (os(iOS) || os(macOS))
import Foundation
import CoreBluetooth
import OSLog

/// Production BLETransport that drives a CBCentralManager. Owns the
/// CB delegates internally; LooiSession sees only the BLETransport
/// surface. Single connected-peripheral assumption (Looi pairs 1:1).
///
/// `@unchecked Sendable`: all mutable state is guarded by `NSLock.withLock`.
/// CB delegate callbacks run on `.main`; async public methods also run on
/// `.main` (defaultIsolation = MainActor). The lock provides cross-boundary
/// safety for the AsyncStream continuations used in non-async computed vars.
public final class CoreBluetoothTransport: NSObject, BLETransport, @unchecked Sendable {

    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.cb-transport")
    private var manager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var discoveredServices: [CBService] = []
    private var _radioState: BLERadioState = .unknown

    private var discoveryContinuations: [AsyncStream<DiscoveredPeripheral>.Continuation] = []
    private var subscriptionContinuations: [CBUUID: [AsyncStream<Data>.Continuation]] = [:]
    private var disconnectionContinuations: [AsyncStream<DisconnectionReason>.Continuation] = []
    private var pendingConnect: CheckedContinuation<Void, Error>?
    private var pendingDiscover: CheckedContinuation<Void, Error>?
    private var pendingReads: [CBUUID: CheckedContinuation<Data, Error>] = [:]
    private let lock = NSLock()
    private var currentNameFilter: String = ""

    public override init() {
        super.init()
        // .main queue keeps delegate callbacks on the main thread, matching
        // the M0.5 BLECentral behavior and defaultIsolation = MainActor.
        self.manager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - BLETransport: radioState

    public var radioState: BLERadioState {
        get async {
            lock.withLock { _radioState }
        }
    }

    // MARK: - BLETransport: disconnections

    public var disconnections: AsyncStream<DisconnectionReason> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            lock.withLock {
                disconnectionContinuations.append(continuation)
            }
        }
    }

    // MARK: - BLETransport: scan / stopScan

    public func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            lock.withLock {
                discoveryContinuations.append(continuation)
                currentNameFilter = nameFilter
            }
            manager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            logger.info("scan: started (filter=\(nameFilter, privacy: .public))")
        }
    }

    public func stopScan() async {
        manager.stopScan()
        let conts = lock.withLock { () -> [AsyncStream<DiscoveredPeripheral>.Continuation] in
            let c = discoveryContinuations
            discoveryContinuations.removeAll()
            return c
        }
        for cont in conts { cont.finish() }
        logger.info("scan: stopped")
    }

    // MARK: - BLETransport: connect / disconnect

    public func connect(_ id: UUID) async throws {
        guard let peripheral = manager.retrievePeripherals(withIdentifiers: [id]).first else {
            throw LooiError.peripheralNotFound(timeout: .zero)
        }
        peripheral.delegate = self
        connectedPeripheral = peripheral
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.withLock { pendingConnect = cont }
            manager.connect(peripheral, options: nil)
        }
    }

    public func disconnect() async {
        guard let p = connectedPeripheral else { return }
        manager.cancelPeripheralConnection(p)
        connectedPeripheral = nil
        discoveredServices.removeAll()
    }

    // MARK: - BLETransport: discoverServicesAndCharacteristics

    public func discoverServicesAndCharacteristics(timeout: Duration) async throws {
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.withLock { pendingDiscover = cont }
            p.discoverServices(nil)
        }
        // Allow remaining characteristics to enumerate after the first
        // didDiscoverCharacteristicsFor callback resumes the continuation.
        try await Task.sleep(for: .milliseconds(500))
    }

    // MARK: - BLETransport: write / read / subscribe

    public func write(_ data: Data, to characteristic: CBUUID, type: WriteType) async throws {
        guard let char = findCharacteristic(characteristic) else {
            // Task 4 adaptation: characteristicMissing takes String (uuidString)
            throw LooiError.characteristicMissing(characteristic.uuidString)
        }
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        let cbType: CBCharacteristicWriteType = (type == .withResponse) ? .withResponse : .withoutResponse
        p.writeValue(data, for: char, type: cbType)
    }

    public func read(from characteristic: CBUUID) async throws -> Data {
        guard let char = findCharacteristic(characteristic) else {
            // Task 4 adaptation: characteristicMissing takes String (uuidString)
            throw LooiError.characteristicMissing(characteristic.uuidString)
        }
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            lock.withLock { pendingReads[characteristic] = cont }
            p.readValue(for: char)
        }
    }

    public func subscribe(to characteristic: CBUUID) async throws -> AsyncStream<Data> {
        guard let char = findCharacteristic(characteristic) else {
            // Task 4 adaptation: characteristicMissing takes String (uuidString)
            throw LooiError.characteristicMissing(characteristic.uuidString)
        }
        guard let p = connectedPeripheral else {
            throw LooiError.sessionNotReady(state: .disconnected)
        }
        p.setNotifyValue(true, for: char)
        return AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            lock.withLock {
                subscriptionContinuations[characteristic, default: []].append(continuation)
            }
        }
    }

    // MARK: - Private helpers

    private func findCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        discoveredServices.flatMap { $0.characteristics ?? [] }.first { $0.uuid == uuid }
    }

    private func translate(_ state: CBManagerState) -> BLERadioState {
        switch state {
        case .unknown:       return .unknown
        case .resetting:     return .unknown
        case .unsupported:   return .unsupported
        case .unauthorized:  return .unauthorized
        case .poweredOff:    return .poweredOff
        case .poweredOn:     return .poweredOn
        @unknown default:    return .unknown
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension CoreBluetoothTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        lock.withLock { _radioState = translate(central.state) }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            let c = pendingConnect; pendingConnect = nil; return c
        }
        cont?.resume()
        logger.info("connect: connected to \(peripheral.identifier, privacy: .public)")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            let c = pendingConnect; pendingConnect = nil; return c
        }
        let desc = error?.localizedDescription ?? "unknown error"
        // Task 4 adaptation: connectionFailed takes underlyingDescription: String
        cont?.resume(throwing: LooiError.connectionFailed(underlyingDescription: desc))
        logger.error("connect: failed — \(desc, privacy: .public)")
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"
        let filter = lock.withLock { currentNameFilter }
        if !filter.isEmpty, !name.uppercased().contains(filter.uppercased()) {
            return
        }
        // Store as [String] (uuidString) — CBUUID is not Sendable in Swift 6
        let services = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
            .map { $0.uuidString }
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let p = DiscoveredPeripheral(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            advertisedServices: services,
            manufacturerData: mfg,
            lastSeen: Date()
        )
        let conts = lock.withLock { discoveryContinuations }
        for cont in conts { cont.yield(p) }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let reason: DisconnectionReason
        if let error {
            reason = .error(error.localizedDescription)
            logger.warning("disconnect: error — \(error.localizedDescription, privacy: .public)")
        } else {
            reason = .clean
            logger.info("disconnect: clean")
        }
        connectedPeripheral = nil
        discoveredServices.removeAll()
        let conts = lock.withLock { disconnectionContinuations }
        for cont in conts { cont.yield(reason) }
    }
}

// MARK: - CBPeripheralDelegate

extension CoreBluetoothTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                let c = pendingDiscover; pendingDiscover = nil; return c
            }
            // Task 4 adaptation: connectionFailed takes underlyingDescription: String
            cont?.resume(throwing: LooiError.connectionFailed(
                underlyingDescription: error.localizedDescription
            ))
            return
        }
        discoveredServices = peripheral.services ?? []
        for s in discoveredServices {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                let c = pendingDiscover; pendingDiscover = nil; return c
            }
            // Task 4 adaptation: connectionFailed takes underlyingDescription: String
            cont?.resume(throwing: LooiError.connectionFailed(
                underlyingDescription: error.localizedDescription
            ))
            return
        }
        // Refresh discoveredServices snapshot so findCharacteristic sees updated chars.
        discoveredServices = peripheral.services ?? []
        // Resume after first service's chars enumerate; sleep in
        // discoverServicesAndCharacteristics covers remaining services.
        let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            let c = pendingDiscover; pendingDiscover = nil; return c
        }
        cont?.resume()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            let pr = lock.withLock { pendingReads.removeValue(forKey: characteristic.uuid) }
            // Task 4 adaptation: writeFailed takes (String, underlyingDescription: String)
            pr?.resume(throwing: LooiError.writeFailed(
                characteristic.uuid.uuidString,
                underlyingDescription: error.localizedDescription
            ))
            return
        }
        let value = characteristic.value ?? Data()

        // Resolve any pending read first.
        let pr = lock.withLock { pendingReads.removeValue(forKey: characteristic.uuid) }
        if let pr {
            pr.resume(returning: value)
            return
        }

        // Otherwise it's a notification — fan out to subscribers.
        let conts = lock.withLock { subscriptionContinuations[characteristic.uuid] ?? [] }
        for cont in conts { cont.yield(value) }
    }
}

#endif
