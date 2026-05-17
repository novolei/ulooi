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

    /// Latest cliff state — stubbed as `.grounded` here; Task 10 replaces this
    /// with a live reference from `SensorController.cliffState` once the sensor
    /// pipeline is wired. `MotionController.cliffStateProvider` reads this field.
    public private(set) var cliffState: CliffState = .grounded

    // MARK: - Controllers

    /// Owns the FED0 30ms motor heartbeat and the cliff hard-block.
    /// Constructed in `init`; lifecycle (start/stop) driven by session state.
    public let motion: MotionController

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

    // MARK: - Init

    public init(transport: BLETransport) {
        self.transport = transport
        self.machine = SessionStateMachine()

        // Two-step capture pattern: construct MotionController with a stub
        // closure, then reassign that closure to read self.cliffState.
        // This avoids referencing `self` before all stored properties are init'd.
        var cliffProvider: () -> CliffState = { .grounded }
        self.motion = MotionController(
            transport: transport,
            cliffStateProvider: { cliffProvider() }
        )

        // Mirror machine.state into self.state and drive the heartbeat lifecycle.
        // The Task hop ensures both assignments land on @MainActor even if
        // onTransition fires from a background continuation.
        self.machine.onTransition = { [weak self] from, to in
            Task { @MainActor [weak self] in
                self?.state = to
                self?.handleStateTransition(from: from, to: to)
            }
        }

        // Now that self is fully initialised, wire the cliff provider to
        // read self.cliffState. Task 10 replaces this with SensorController.
        cliffProvider = { [weak self] in self?.cliffState ?? .grounded }

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
            self.scanTask?.cancel()
            self.connectTask?.cancel()
            await self.transport.disconnect()
            try? self.machine.transition(to: .disconnected)
            self.currentPeripheral = nil
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

        // Handshake
        do {
            try machine.transition(to: .handshaking)
            _ = try await HandshakeRunner(transport: transport).run()
        } catch {
            logger.error("runConnect: handshake failed: \(String(describing: error), privacy: .public)")
            try? machine.transition(to: .disconnected)
            return
        }

        try? machine.transition(to: .ready)
    }

    /// Called when the transport fires a disconnection event.
    /// Task 11 upgrades this to .reconnecting with exponential backoff.
    private func handleDisconnection(_ reason: DisconnectionReason) async {
        logger.info("disconnection (\(String(describing: reason), privacy: .public)) from \(self.state.description, privacy: .public)")
        try? machine.transition(to: .disconnected)
        currentPeripheral = nil
    }

    /// Drives MotionController lifecycle as the session state changes.
    ///
    /// - I2: `.ready` entry → `motion.startHeartbeat()`
    /// - I4: `.ready` exit  → `motion.cancelHeartbeat()`
    /// - I6: any `.ready` → non-`.ready` transition → `motion.emergencyStop()`
    ///       (spawned as a Task so the state machine is not blocked on the BLE write)
    private func handleStateTransition(from: SessionState, to: SessionState) {
        switch (from.isReady, to.isReady) {
        case (false, true):
            // I2: entering .ready — start the motor heartbeat.
            motion.startHeartbeat()
        case (true, false):
            // I4: leaving .ready — cancel the heartbeat immediately …
            motion.cancelHeartbeat()
            // I6: … then send one confirmed stop write so the robot halts.
            Task { await motion.emergencyStop() }
        default:
            break
        }
    }
}
