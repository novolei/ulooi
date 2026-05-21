import Foundation
import Observation
import OSLog

/// Owns the 30ms motor heartbeat to FED0 and enforces the cliff hard-block.
///
/// Per spec §5.3 + §9.1: `setMotion` calls throw `LooiError.cliffLocked` when
/// `cliffStateProvider()` returns a suspended state. The heartbeat is the ONLY
/// thing writing FED0 — callers update `currentMotion`, the heartbeat picks it
/// up on the next tick (≤30 ms latency). `stop()` bypasses the cliff check
/// because stopping is always safe.
///
/// Swift 6 notes:
/// - `@MainActor` by package default (`defaultIsolation(MainActor.self)`).
/// - `heartbeatTask` is `@ObservationIgnored nonisolated(unsafe)` so deinit
///   can cancel it without a MainActor hop (`.cancel()` is thread-safe on any
///   Sendable `Task` value). All writes to it happen on @MainActor.
/// - The `cliffStateProvider` closure returns a value type (`CliffState`) —
///   no Sendable issues crossing the actor boundary.
@MainActor
@Observable
public final class MotionController {

    // MARK: - Dependencies

    private let transport: BLETransport
    private let cliffStateProvider: () -> CliffState
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.motion")

    // MARK: - Observable state

    public private(set) var currentMotion: MotionState = .stop
    public private(set) var heartbeatTicks: Int = 0

    // @ObservationIgnored prevents the @Observable macro from wrapping this
    // in @ObservationTracked (which would conflict with nonisolated(unsafe)).
    // nonisolated(unsafe) allows deinit and Task bodies to call .cancel()
    // without requiring a MainActor hop. All writes happen on @MainActor.
    @ObservationIgnored nonisolated(unsafe) private var heartbeatTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - transport: The BLE transport used to write FED0.
    ///   - cliffStateProvider: Called by `setMotion` to obtain the current cliff
    ///     state. Typically a closure that reads `LooiSession.cliffState` (Task 10
    ///     wires it to `SensorController.cliffState`; Task 8 stubs it as `.grounded`).
    public init(transport: BLETransport, cliffStateProvider: @escaping () -> CliffState) {
        self.transport = transport
        self.cliffStateProvider = cliffStateProvider
    }

    deinit {
        heartbeatTask?.cancel()
    }

    // MARK: - Motion control

    /// Update the motion the heartbeat will broadcast.
    ///
    /// Throws `LooiError.cliffLocked(directions:)` when any wheel is suspended
    /// (hard-block per spec §9.1). Does NOT mutate `currentMotion` on throw.
    public func setMotion(_ motion: MotionState) throws {
        let cliff = cliffStateProvider()
        if cliff.isSuspended && motion != .stop {
            throw LooiError.cliffLocked(directions: cliff)
        }
        currentMotion = motion
    }

    /// Move forward. Throws `cliffLocked` when suspended.
    public func forward(speed: Int8 = 127) throws {
        try setMotion(MotionState(
            label: "Forward",
            data: LooiCommand.Movement.encode(speed: speed, turn: 0)
        ))
    }

    /// Move backward. Throws `cliffLocked` when suspended.
    public func backward(speed: Int8 = 127) throws {
        try setMotion(MotionState(
            label: "Backward",
            data: LooiCommand.Movement.encode(speed: -speed, turn: 0)
        ))
    }

    /// Spin left (counter-clockwise). Throws `cliffLocked` when suspended.
    public func spinLeft(speed: Int8 = 127) throws {
        try setMotion(MotionState(
            label: "SpinLeft",
            data: LooiCommand.Movement.encode(speed: 0, turn: speed)
        ))
    }

    /// Spin right (clockwise). Throws `cliffLocked` when suspended.
    public func spinRight(speed: Int8 = 127) throws {
        try setMotion(MotionState(
            label: "SpinRight",
            data: LooiCommand.Movement.encode(speed: 0, turn: -speed)
        ))
    }

    /// Always safe to call — bypasses the cliff check and sets `currentMotion`
    /// to `.stop` immediately. The heartbeat will pick it up on the next tick.
    public func stop() {
        currentMotion = .stop
    }

    // MARK: - Heartbeat

    /// Begin the 30ms motor heartbeat to FED0 using `.withoutResponse` writes.
    ///
    /// Safe to call repeatedly — cancels any prior heartbeat task first.
    /// Called by `LooiSession` when the session transitions into `.ready` (I2).
    public func startHeartbeat() {
        cancelHeartbeat()
        heartbeatTicks = 0
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            self.logger.info("motor heartbeat: starting (30ms, .withoutResponse)")
            while !Task.isCancelled {
                let motion = self.currentMotion
                do {
                    try await self.transport.write(
                        motion.data,
                        to: LooiProtocol.Char.movement,
                        type: .withoutResponse
                    )
                    self.heartbeatTicks += 1
                } catch {
                    self.logger.warning(
                        "motor heartbeat: write failed at tick \(self.heartbeatTicks): \(String(describing: error), privacy: .public)"
                    )
                    break
                }
                try? await Task.sleep(for: LooiProtocol.Timing.motorHeartbeatInterval)
            }
            self.logger.info("motor heartbeat: stopped after \(self.heartbeatTicks) ticks")
        }
    }

    /// Cancel the heartbeat task. Called when `LooiSession` leaves `.ready` (I4).
    public func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Emergency stop

    /// Immediately sets `currentMotion` to `.stop` and sends one explicit stop
    /// write to FED0 using `.withResponse` so delivery is confirmed.
    ///
    /// Called by `LooiSession`'s I6 hook on every `.ready` → non-`.ready`
    /// transition (cliff, disconnect, reconnect). Safe to call from a `Task` on
    /// any executor — the write is awaited before returning.
    public func emergencyStop() async {
        currentMotion = .stop
        try? await transport.write(
            LooiCommand.Movement.stop,
            to: LooiProtocol.Char.movement,
            type: .withResponse
        )
    }
}
