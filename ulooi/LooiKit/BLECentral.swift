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

    // Discovery filter. Default focuses on LOOI to avoid noise (your
    // environment has 20+ BLE devices broadcasting). Set to empty string
    // to show all discovered peripherals. Looi advertises with NO service
    // UUIDs (`services=[no-svc-adv]`), so we can't use the OS-level
    // `scanForPeripherals(withServices:)` filter — name match is the only
    // signal. Comparison is case-insensitive substring.
    var nameFilter: String = "LOOI"

    // Visible to delegate extensions in the same module.
    var central: CBCentralManager!
    let log = ProbeLog.shared

    // Motor heartbeat task — started by runLooiInit, cancelled by didDisconnect.
    // Writes Movement.stop to FED0 every 30ms to satisfy Looi's keep-alive
    // expectation. Without this, Looi drops the connection within seconds even
    // after a successful INIT handshake (per andrey-tut: "Heartbeat required
    // every ~30ms"). Mutable from the same file only — internal API.
    var heartbeatTask: Task<Void, Never>?

    // Diagnostic counters for the heartbeat — visible to delegate extensions
    // so didDisconnect can log how many ticks fired before Looi dropped us.
    var heartbeatTicks: Int = 0
    var heartbeatStartTime: Date?

    // Battery polling task — parallel keep-alive that andrey-tut's waasd.py
    // runs alongside the motor heartbeat. Reads FED8 every 4s. Likely
    // required for Looi to consider the connection "actively monitored",
    // not just "receiving writes". Started by runLooiInit, cancelled on
    // disconnect.
    var batteryPollTask: Task<Void, Never>?
    var batteryPolls: Int = 0

    // Persisted pairing — saved after a successful runLooiInit, loaded on
    // app launch. centralManagerDidUpdateState auto-reconnects to this Looi
    // when BLE comes up so the user doesn't have to manually Scan + Connect
    // on every app launch. Use forgetPairing() to clear.
    private enum UserDefaultKeys {
        static let pairedPeripheralID = "ulooi.last.paired.peripheral.id"
    }

    var pairedPeripheralID: UUID? {
        get {
            UserDefaults.standard.string(forKey: UserDefaultKeys.pairedPeripheralID)
                .flatMap(UUID.init(uuidString:))
        }
        set {
            if let new = newValue {
                UserDefaults.standard.set(new.uuidString, forKey: UserDefaultKeys.pairedPeripheralID)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultKeys.pairedPeripheralID)
            }
        }
    }

    func forgetPairing() {
        if let prior = pairedPeripheralID {
            DevLog.event("forgetting paired Looi: \(prior.uuidString.prefix(8))", channel: DevLog.ble)
        }
        pairedPeripheralID = nil
    }

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
        cancelBatteryPoll()
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

        // Step 0 of andrey-tut's sequence (we previously skipped this):
        // read the standard 2A29 (Manufacturer Name) char. Comment in
        // waasd.py: "Wake up macOS Bluetooth cache". On iOS it may not be
        // load-bearing but it's cheap and mirrors the working Python flow.
        await readDeviceInfoManufacturer()

        await runLooiInit()
    }

    /// Read the standard Device Info Service Manufacturer Name characteristic
    /// (0x2A29). Andrey-tut's waasd.py does this BEFORE the FEDA handshake;
    /// wrapped in try/except in Python — failures are ignored.
    func readDeviceInfoManufacturer() async {
        guard let char = findCharacteristic(LooiProtocol.Char.deviceInfoManufacturer),
              let peripheral = connectedPeripheral else {
            DevLog.warn("readDeviceInfoManufacturer: 2A29 char or peripheral not available", channel: DevLog.ble)
            return
        }
        DevLog.event("step 0/4: read 2A29 manufacturer (wake-up read, match andrey-tut)", channel: DevLog.ble)
        peripheral.readValue(for: char)
        try? await Task.sleep(for: .milliseconds(150))
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
        try? await Task.sleep(for: .milliseconds(100))  // match andrey-tut's 0.1s

        DevLog.event("Looi INIT 2/3 — subscribing FED5 + FED9", channel: DevLog.ble)
        subscribe(to: sensors)
        subscribe(to: telemetry)
        // Bumped 150 → 300ms. CBPeripheral.setNotifyValue returns immediately
        // and iOS performs the descriptor write asynchronously. The Python
        // equivalent (bleak.start_notify) blocks until the descriptor write
        // completes, so in waasd.py the next write naturally serialized
        // behind it. On iOS we need a longer pause to give iOS time to
        // actually enable both notifications before sending 0x03.
        try? await Task.sleep(for: .milliseconds(300))

        DevLog.event("Looi INIT 3/3 — writing 0x03 to FEDA", channel: DevLog.ble)
        write(LooiProtocol.Handshake.phase2Data, to: handshake)

        DevLog.event(
            "Looi INIT complete — starting motor heartbeat + battery poll keep-alives.",
            channel: DevLog.ble
        )

        // andrey-tut runs BOTH of these as parallel background tasks. Just one
        // (motor heartbeat) isn't enough — Looi drops after ~2s with only
        // writes to FED0. The battery POLL on FED8 every 4s is the second
        // missing piece (per re-read of waasd.py).
        startMotorHeartbeat()
        startBatteryPoll()

        // Save pairing so next launch can auto-reconnect without manual Scan
        // + Connect. Write only if changed to avoid UserDefaults churn.
        if let p = connectedPeripheral, pairedPeripheralID != p.identifier {
            pairedPeripheralID = p.identifier
            DevLog.event(
                "pairing saved: \(p.identifier.uuidString.prefix(8)) — will auto-reconnect on next app launch",
                channel: DevLog.ble
            )
        }
    }

    /// Start the 30ms motor heartbeat that keeps Looi connected. Always writes
    /// `LooiCommand.Movement.stop` (00 00) — motors stay idle but Looi sees
    /// activity. Cancelled automatically by `didDisconnect`. Safe to call
    /// multiple times (cancels any prior task first).
    ///
    /// Uses `.withResponse` writes (slower than .withoutResponse but
    /// guaranteed-delivery). Previously `.withoutResponse` was tried; suspected
    /// of being silently queued/dropped by iOS BLE stack when the connection
    /// isn't fully ready, which would explain why Looi still dropped despite
    /// the heartbeat "running". `.withResponse` blocks until the peripheral
    /// acks, so we KNOW each write reached Looi.
    func startMotorHeartbeat() {
        cancelMotorHeartbeat()
        heartbeatTicks = 0
        heartbeatStartTime = Date()
        heartbeatTask = Task { @MainActor in
            DevLog.event(
                "motor heartbeat: starting (FED0, 30ms target, STOP, .withResponse)",
                channel: DevLog.ble
            )
            while !Task.isCancelled {
                guard let peripheral = self.connectedPeripheral,
                      peripheral.state == .connected,
                      let movementChar = self.findCharacteristic(LooiProtocol.Char.movement)
                else {
                    let elapsed = self.heartbeatStartTime.map {
                        String(format: "%.2f", Date().timeIntervalSince($0))
                    } ?? "?"
                    DevLog.event(
                        "motor heartbeat: connection lost after \(self.heartbeatTicks) ticks (\(elapsed)s)",
                        channel: DevLog.ble
                    )
                    break
                }
                // .withResponse: each write blocks the queue until ack — slower
                // but guaranteed-delivery. Looi can't claim "no commands" while
                // we're getting acks.
                peripheral.writeValue(LooiCommand.Movement.stop, for: movementChar, type: .withResponse)
                self.heartbeatTicks += 1
                // Log every tick for first 10 (to see start-up timing) then
                // every 25 (to confirm ongoing).
                if self.heartbeatTicks <= 10 || self.heartbeatTicks.isMultiple(of: 25) {
                    let elapsed = self.heartbeatStartTime.map {
                        String(format: "%.2f", Date().timeIntervalSince($0))
                    } ?? "?"
                    DevLog.event(
                        "motor heartbeat: tick \(self.heartbeatTicks) @ \(elapsed)s",
                        channel: DevLog.ble
                    )
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

    /// Start the 4-second battery poll task. Reads FED8 (Looi's custom battery
    /// characteristic) at the same cadence andrey-tut's waasd.py does. Likely
    /// required as a secondary keep-alive signal — without it, motor heartbeat
    /// alone is insufficient to keep Looi connected past ~2.2s.
    func startBatteryPoll() {
        cancelBatteryPoll()
        batteryPolls = 0
        batteryPollTask = Task { @MainActor in
            DevLog.event("battery poll: starting (FED8, 4s interval, match andrey-tut)", channel: DevLog.ble)
            while !Task.isCancelled {
                guard let peripheral = self.connectedPeripheral,
                      peripheral.state == .connected,
                      let batteryChar = self.findCharacteristic(LooiProtocol.Char.battery)
                else {
                    DevLog.event("battery poll: connection lost after \(self.batteryPolls) polls", channel: DevLog.ble)
                    break
                }
                peripheral.readValue(for: batteryChar)
                self.batteryPolls += 1
                DevLog.event("battery poll: read \(self.batteryPolls) (FED8)", channel: DevLog.ble)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Cancel the battery poll task (called by didDisconnect or manual disconnect).
    func cancelBatteryPoll() {
        if batteryPollTask != nil {
            batteryPollTask?.cancel()
            batteryPollTask = nil
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
