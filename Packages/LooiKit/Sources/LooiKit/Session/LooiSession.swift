import Foundation
import Observation
import CoreBluetooth
import OSLog

/// Top-level public type — the iOS app's handle to one paired Looi.
///
/// Owns the SessionState machine, the BLETransport, and (in later tasks)
/// the four Controllers + reconnect policy + handshake. Mutates state
/// only on @MainActor (invariant I1).
///
/// Tasks 8-10 attach MotionController / HeadController / LightController /
/// SensorController. Task 11 upgrades the disconnection handler to
/// .reconnecting with backoff. Task 12 cuts the app over from BLECentral.
@MainActor
@Observable
public final class LooiSession {

    // MARK: - Observable state

    public private(set) var state: SessionState = .disconnected
    public private(set) var currentPeripheral: DiscoveredPeripheral?

    // MARK: - Controllers

    /// Owns the FED0 30ms motor heartbeat and the cliff hard-block.
    /// Constructed in `init`; lifecycle (start/stop) driven by session state.
    public let motion: MotionController

    /// Controls head pitch via FED1.
    public let head: HeadController

    /// Controls headlight brightness via FED2.
    public let light: LightController

    /// Decodes FED5 (sensors) and FED9 (telemetry) streams; publishes
    /// cliffState / imu / batteryPercent / lastTouchEvent.
    public let sensor: SensorController

    // MARK: - Reconnect policy + persisted pairing

    public let reconnectPolicy: ReconnectPolicy

    /// UserDefaults-backed last paired peripheral. Automatically attempted
    /// first on reconnect and on next app launch.
    public var pairedPeripheralID: UUID? {
        get {
            UserDefaults.standard.string(forKey: Self.pairedKey)
                .flatMap(UUID.init(uuidString:))
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v.uuidString, forKey: Self.pairedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pairedKey)
            }
        }
    }

    /// Clear the stored paired peripheral (e.g. on factory-reset flow).
    public func forgetPairing() { pairedPeripheralID = nil }

    private static let pairedKey = "looikit.last.paired.peripheral.id"

    // MARK: - Private fields

    private let transport: BLETransport
    private let machine: SessionStateMachine
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.session")

    // @ObservationIgnored so the @Observable macro does not wrap these in
    // @ObservationTracked (which would prevent nonisolated(unsafe)).
    // nonisolated(unsafe) allows deinit to call .cancel() without a
    // MainActor hop. All writes happen on @MainActor; Task.cancel() is
    // thread-safe on any Sendable Task value.
    @ObservationIgnored nonisolated(unsafe) private var scanTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var connectTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var disconnectionWatcher: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var reconnectTask: Task<Void, Never>?

    /// Set to true during user-initiated disconnect so that transport
    /// disconnection events (which fire when we call transport.disconnect())
    /// do not kick off a reconnect loop.
    private var isDisconnecting = false

    // MARK: - Init

    public init(transport: BLETransport, reconnectPolicy: ReconnectPolicy = .default) {
        self.transport = transport
        self.reconnectPolicy = reconnectPolicy
        self.machine = SessionStateMachine()

        // Two-step capture pattern: construct MotionController with a stub
        // closure, then reassign that closure to read sensor.cliffState once
        // sensor is fully initialised. This avoids referencing `self` before
        // all stored properties are init'd.
        var cliffProvider: () -> CliffState = { .grounded }
        self.motion = MotionController(
            transport: transport,
            cliffStateProvider: { cliffProvider() }
        )
        self.head = HeadController(transport: transport)
        self.light = LightController(transport: transport)
        self.sensor = SensorController(transport: transport)

        // Mirror machine.state into self.state and drive the controller lifecycle.
        // The Task hop ensures both assignments land on @MainActor even if
        // onTransition fires from a background continuation.
        self.machine.onTransition = { [weak self] from, to in
            Task { @MainActor [weak self] in
                self?.state = to
                self?.handleStateTransition(from: from, to: to)
            }
        }

        // Now that self is fully initialised, wire the cliff provider to
        // read SensorController.cliffState.
        cliffProvider = { [weak self] in self?.sensor.cliffState ?? .grounded }

        // Watch for transport-level disconnections and react appropriately.
        // Task.detached + explicit @MainActor ensures the for-await loop
        // runs on MainActor without inheriting any ambient isolation from
        // the spawning context (avoids Swift 6 isolation-mismatch warnings).
        let capturedTransport = transport
        self.disconnectionWatcher = Task { @MainActor [weak self] in
            for await reason in capturedTransport.disconnections {
                await self?.handleDisconnection(reason)
            }
        }
    }

    deinit {
        disconnectionWatcher?.cancel()
        scanTask?.cancel()
        connectTask?.cancel()
        reconnectTask?.cancel()
        // heartbeatTask is owned by MotionController; its deinit cancels it.
    }

    // MARK: - Public API

    /// Start scanning and auto-connect to the first peripheral whose name
    /// contains `nameFilter` (case-insensitive).
    public func startScanAndConnect(nameFilter: String = "LOOI") {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            await self?.runScanAndConnect(nameFilter: nameFilter)
        }
    }

    /// Manually connect to a specific peripheral by UUID (e.g. from a
    /// previously paired peripheral ID stored on device).
    public func connect(to id: UUID) {
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.runConnect(id: id, fromState: nil)
        }
    }

    /// User-initiated disconnect. Cancels in-flight work and drops to
    /// .disconnected immediately. Idempotent.
    public func disconnect() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Flag user intent before calling transport.disconnect() — the
            // transport fires a disconnection event synchronously in tests,
            // and handleDisconnection must not start a reconnect loop for a
            // user-initiated disconnect.
            self.isDisconnecting = true
            self.scanTask?.cancel()
            self.connectTask?.cancel()
            self.reconnectTask?.cancel()
            await self.transport.disconnect()
            try? self.machine.transition(to: .disconnected)
            self.currentPeripheral = nil
            self.isDisconnecting = false
        }
    }

    // MARK: - Internal flow

    private func runScanAndConnect(nameFilter: String) async {
        do {
            try machine.transition(to: .scanning)
        } catch {
            logger.error("runScanAndConnect: cannot transition to .scanning from \(self.machine.state.description, privacy: .public)")
            return
        }

        let stream = transport.scan(nameFilter: nameFilter)
        for await peripheral in stream {
            if Task.isCancelled { return }
            currentPeripheral = peripheral
            await transport.stopScan()
            await runConnect(id: peripheral.id, fromState: .scanning)
            return
        }
    }

    /// Drives the connect → discover → handshake → ready pipeline.
    ///
    /// - Parameter fromState: Pass `.scanning` when called from
    ///   `runScanAndConnect` (the machine is already in .scanning, so only
    ///   the .connecting transition is needed). Pass `nil` when called from
    ///   `connect(to:)` directly — the machine starts from .disconnected,
    ///   so .scanning → .connecting is performed.
    private func runConnect(id: UUID, fromState: SessionState?) async {
        do {
            if fromState == nil {
                // Direct connect(to:) path: disconnected → scanning → connecting.
                try machine.transition(to: .scanning)
                try machine.transition(to: .connecting)
            } else {
                // Called from runScanAndConnect: already .scanning → .connecting.
                try machine.transition(to: .connecting)
            }
        } catch {
            logger.error("runConnect: invalid transition from \(self.machine.state.description, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        // Connect
        do {
            try await transport.connect(id)
        } catch {
            logger.error("runConnect: transport.connect failed: \(String(describing: error), privacy: .public)")
            try? machine.transition(to: .disconnected)
            return
        }

        // Discover services + characteristics
        do {
            try machine.transition(to: .discovering)
            try await transport.discoverServicesAndCharacteristics(timeout: .seconds(4))
        } catch {
            logger.error("runConnect: discover failed: \(String(describing: error), privacy: .public)")
            try? machine.transition(to: .disconnected)
            return
        }

        // Handshake — capture streams and pipe into SensorController.
        do {
            try machine.transition(to: .handshaking)
            let streams = try await HandshakeRunner(transport: transport).run()
            sensor.consume(sensors: streams.sensors, telemetry: streams.telemetry)
        } catch {
            logger.error("runConnect: handshake failed: \(String(describing: error), privacy: .public)")
            try? machine.transition(to: .disconnected)
            return
        }

        try? machine.transition(to: .ready)
        // Persist the paired peripheral so reconnect can target it directly.
        pairedPeripheralID = id
    }

    /// Called when the transport fires a disconnection event.
    /// Enters .reconnecting with exponential backoff unless the disconnect
    /// was user-initiated (isDisconnecting) or the session is already .disconnected.
    private func handleDisconnection(_ reason: DisconnectionReason) async {
        logger.info("disconnection: \(String(describing: reason), privacy: .public) from \(self.state.description, privacy: .public)")
        // Guard: do not start a reconnect loop for user-initiated disconnects
        // or if we're already in .disconnected state.
        guard !isDisconnecting, state != .disconnected else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.runReconnectLoop()
        }
    }

    private func runReconnectLoop() async {
        var attempt = 1
        while !Task.isCancelled {
            do {
                try machine.transition(to: .reconnecting(attempt: attempt))
            } catch {
                try? machine.transition(to: .disconnected)
                return
            }

            guard let delay = reconnectPolicy.delay(forAttempt: attempt) else {
                // Exhausted the backoff window — give up.
                try? machine.transition(to: .disconnected)
                return
            }
            try? await Task.sleep(for: delay)
            if Task.isCancelled { return }

            // Try paired UUID first; fall back to scan.
            if let pairedID = pairedPeripheralID {
                try? machine.transition(to: .scanning)
                await runConnect(id: pairedID, fromState: .scanning)
                if state.isReady { return }
            } else {
                startScanAndConnect()
                try? await Task.sleep(for: .seconds(2))
                if state.isReady { return }
            }
            attempt += 1
        }
    }

    /// Drives MotionController and SensorController lifecycle as the session
    /// state changes.
    ///
    /// - I2: `.ready` entry → `motion.startHeartbeat()`
    /// - I3: `.ready` entry → `sensor.startBatteryPoll()`
    /// - I4: `.ready` exit  → `motion.cancelHeartbeat()` + `sensor.cancelBatteryPoll()` + `sensor.stopConsuming()`
    /// - I6: any `.ready` → non-`.ready` transition → `motion.emergencyStop()`
    ///       (spawned as a Task so the state machine is not blocked on the BLE write)
    private func handleStateTransition(from: SessionState, to: SessionState) {
        switch (from.isReady, to.isReady) {
        case (false, true):
            // I2: entering .ready — start the motor heartbeat.
            motion.startHeartbeat()
            // I3: entering .ready — start the 4s battery poll.
            sensor.startBatteryPoll()
        case (true, false):
            // I4: leaving .ready — cancel the heartbeat and sensor tasks immediately …
            motion.cancelHeartbeat()
            sensor.cancelBatteryPoll()
            sensor.stopConsuming()
            // I6: … then send one confirmed stop write so the robot halts.
            Task { await motion.emergencyStop() }
        default:
            break
        }
    }
}
