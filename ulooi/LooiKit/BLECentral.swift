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

    // These four are written by the BLE delegate extensions
    // (BLECentral+CentralDelegate.swift / BLECentral+PeripheralDelegate.swift)
    // as events arrive on the MainActor. Outside callers should treat them
    // as read-only. We can't use `private(set)` because Swift's `private`
    // is file-scoped and the delegate extensions live in sibling files.
    var state: State = .unknown
    var discoveries: [UUID: Discovery] = [:]
    var connectedPeripheral: CBPeripheral?
    var discoveredServices: [CBService] = []

    // Only mutated in this file (startScan / stopScan).
    private(set) var isScanning: Bool = false

    // Visible to delegate extensions in the same module.
    var central: CBCentralManager!
    let log = ProbeLog.shared

    // Motor heartbeat task — started by runLooiInit, cancelled by didDisconnect.
    // Writes Movement.stop to FED0 every 30ms to satisfy Looi's keep-alive
    // expectation. Without this, Looi drops the connection within seconds even
    // after a successful INIT handshake (per andrey-tut: "Heartbeat required
    // every ~30ms"). Mutable from the same file only — internal API.
    var heartbeatTask: Task<Void, Never>?

    override init() {
        super.init()
        // queue=.main keeps delegate callbacks on the main actor (no thread hop).
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scan

    func startScan(serviceFilter: [CBUUID]? = nil) {
        guard state == .poweredOn else {
            DevLog.warn("startScan: BLE not powered on (state=\(state.rawValue))")
            return
        }
        DevLog.event("scan: start (filter=\(serviceFilter?.map { $0.uuidString }.joined(separator: ",") ?? "any"))")
        discoveries.removeAll()
        isScanning = true
        central.scanForPeripherals(
            withServices: serviceFilter,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        guard isScanning else { return }
        DevLog.event("scan: stop (found \(discoveries.count))")
        central.stopScan()
        isScanning = false
    }

    // MARK: - Connect / Disconnect

    func connect(_ id: UUID) {
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else {
            DevLog.error("connect: peripheral \(id) not retrievable; scan first")
            return
        }
        DevLog.event("connect: \(peripheral.identifier) name=\(peripheral.name ?? "?")")
        peripheral.delegate = self
        connectedPeripheral = peripheral
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let p = connectedPeripheral else { return }
        DevLog.event("disconnect: \(p.identifier)")
        cancelMotorHeartbeat()
        central.cancelPeripheralConnection(p)
    }

    // MARK: - GATT discovery

    func discoverAllServices() {
        guard let p = connectedPeripheral, p.state == .connected else {
            DevLog.warn("discoverAllServices: not connected")
            return
        }
        DevLog.event("discoverServices: requesting all")
        discoveredServices.removeAll()
        p.discoverServices(nil)
    }

    // MARK: - Write / Subscribe

    func write(_ data: Data, to characteristic: CBCharacteristic, type: CBCharacteristicWriteType = .withResponse) {
        guard let p = connectedPeripheral else {
            DevLog.warn("write: not connected")
            return
        }
        DevLog.bytes("write→\(characteristic.uuid.uuidString)", data)
        p.writeValue(data, for: characteristic, type: type)
    }

    func subscribe(to characteristic: CBCharacteristic) {
        guard let p = connectedPeripheral else { return }
        DevLog.event("subscribe: \(characteristic.uuid.uuidString)")
        p.setNotifyValue(true, for: characteristic)
    }

    func unsubscribe(from characteristic: CBCharacteristic) {
        guard let p = connectedPeripheral else { return }
        DevLog.event("unsubscribe: \(characteristic.uuid.uuidString)")
        p.setNotifyValue(false, for: characteristic)
    }

    // MARK: - Looi-specific (move to LooiSession.swift in M1)

    /// Find a discovered characteristic by UUID, scanning all known services.
    /// Returns nil if not yet discovered (run discoverAllServices first).
    func findCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        discoveredServices.flatMap { $0.characteristics ?? [] }.first { $0.uuid == uuid }
    }

    /// Full "connect + auto-init" flow for a Looi peripheral. Bundles the
    /// previously-manual sequence (connect → discover services → write 0x01 →
    /// subscribe sensors+telemetry → write 0x03) into one async call.
    ///
    /// Why: Looi drops the connection within ~2 seconds of connect if the INIT
    /// handshake doesn't complete (sooperchargeforbots README confirms this).
    /// Manually tapping through Inspect → Command → Sense → Command can't keep
    /// up. This method completes the whole thing in <2.5s.
    ///
    /// Uses crude Task.sleep delays for delegate-callback sequencing — for
    /// M0.5 throwaway this is fine; M1 will rewrite with CheckedContinuation
    /// or proper async/await wrappers.
    func connectAndAutoInitLooi(_ id: UUID) async {
        DevLog.event("connectAndAutoInitLooi: starting for \(id.uuidString.prefix(8))", channel: DevLog.ble)
        connect(id)

        // Wait for didConnect + auto-discoverServices to fire. iOS connect
        // typically completes in 200-800ms but Round 1 of the user's first
        // test showed 800ms was sometimes too tight — bumped to 1500ms.
        try? await Task.sleep(for: .milliseconds(1500))

        guard let p = connectedPeripheral, p.state == .connected else {
            DevLog.warn("connectAndAutoInitLooi: not connected after 1500ms — aborting", channel: DevLog.ble)
            return
        }

        // Wait for full service + characteristic enumeration. iOS typically
        // enumerates ~10 services × ~5 chars each in 1-2s.
        try? await Task.sleep(for: .milliseconds(1500))

        await runLooiInit()
    }

    /// Run the Looi INIT handshake against an already-connected peripheral
    /// whose services/chars are already discovered.
    /// Sequence: write 0x01 → FEDA, subscribe FED5+FED9, write 0x03 → FEDA.
    /// ✅ Source: andrey-tut/LOOI-Robot waasd.py, verified.
    func runLooiInit() async {
        guard let handshake = findCharacteristic(LooiProtocol.Char.handshake) else {
            DevLog.warn(
                "runLooiInit: handshake char (FEDA) not found. Run Inspect → Discover all services first, or use Connect+Auto-Init Looi from Scan tab.",
                channel: DevLog.ble
            )
            return
        }
        guard let sensors = findCharacteristic(LooiProtocol.Char.sensors) else {
            DevLog.warn("runLooiInit: sensors char (FED5) not found", channel: DevLog.ble)
            return
        }
        guard let telemetry = findCharacteristic(LooiProtocol.Char.telemetry) else {
            DevLog.warn("runLooiInit: telemetry char (FED9) not found", channel: DevLog.ble)
            return
        }

        DevLog.event("Looi INIT 1/3 — writing 0x01 to FEDA", channel: DevLog.ble)
        write(LooiProtocol.Handshake.phase1Data, to: handshake)
        try? await Task.sleep(for: .milliseconds(150))

        DevLog.event("Looi INIT 2/3 — subscribing FED5 + FED9", channel: DevLog.ble)
        subscribe(to: sensors)
        subscribe(to: telemetry)
        try? await Task.sleep(for: .milliseconds(150))

        DevLog.event("Looi INIT 3/3 — writing 0x03 to FEDA", channel: DevLog.ble)
        write(LooiProtocol.Handshake.phase2Data, to: handshake)

        DevLog.event(
            "Looi INIT complete — starting motor heartbeat to keep connection alive.",
            channel: DevLog.ble
        )

        // CRITICAL: without this heartbeat, Looi drops the connection within
        // ~3 seconds even after a successful INIT handshake. The Looi firmware
        // expects movement commands every ~30ms — interpret silence as
        // "controller died, drop the connection". Writes Movement.stop (00 00)
        // so motors stay idle but the keep-alive contract is satisfied.
        startMotorHeartbeat()
    }

    /// Start the 30ms motor heartbeat that keeps Looi connected. Always writes
    /// `LooiCommand.Movement.stop` (00 00) — motors stay idle but Looi sees
    /// activity. Cancelled automatically by `didDisconnect`. Safe to call
    /// multiple times (cancels any prior task first).
    func startMotorHeartbeat() {
        cancelMotorHeartbeat()
        heartbeatTask = Task { @MainActor in
            DevLog.event("motor heartbeat: starting (FED0, 30ms, STOP)", channel: DevLog.ble)
            var ticks = 0
            while !Task.isCancelled {
                guard let peripheral = self.connectedPeripheral,
                      peripheral.state == .connected,
                      let movementChar = self.findCharacteristic(LooiProtocol.Char.movement)
                else {
                    DevLog.event("motor heartbeat: connection lost or chars missing, stopping", channel: DevLog.ble)
                    break
                }
                // .withoutResponse: don't wait for ack — keep loop fast at 30ms.
                peripheral.writeValue(LooiCommand.Movement.stop, for: movementChar, type: .withoutResponse)
                ticks += 1
                // Periodic heartbeat log every ~3 seconds so we can SEE it's alive
                // without flooding (would be 30 logs/sec otherwise).
                if ticks.isMultiple(of: 100) {
                    DevLog.event("motor heartbeat: \(ticks) ticks sent", channel: DevLog.ble)
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    /// Cancel the motor heartbeat task (called by didDisconnect or manual disconnect).
    func cancelMotorHeartbeat() {
        if heartbeatTask != nil {
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }

    // MARK: - State translation (used by central delegate)

    /// `nonisolated` because it's pure value translation — no state access.
    /// Lets `nonisolated` CB delegate methods call it directly without a
    /// MainActor hop.
    nonisolated static func translate(_ cb: CBManagerState) -> State {
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
