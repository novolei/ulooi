import Foundation
@preconcurrency import CoreBluetooth

/// Abstract BLE I/O surface. Production binds `CoreBluetoothTransport`;
/// tests bind `MockBLETransport`. LooiSession depends on this protocol
/// rather than CoreBluetooth directly so the entire session lifecycle is
/// reachable from unit tests.
///
/// All methods are `async` so the implementation can serialize internally
/// (Mock is a class guarded by NSLock; CoreBluetoothTransport drives a
/// CBCentralManager on a private queue) without exposing locking to callers.
///
/// `@preconcurrency` on the protocol allows conformances to implement methods
/// with CBUUID parameters without Swift 6 raising Sendability errors at the
/// protocol-requirement level — CBUUID is not declared Sendable by CoreBluetooth.
@preconcurrency
public protocol BLETransport: Sendable {

    /// Whether BLE is powered on and authorized. `.poweredOn` is required
    /// before scan/connect can succeed.
    var radioState: BLERadioState { get async }

    /// Start scanning; observe discovered peripherals via the returned stream.
    /// `nameFilter` (case-insensitive substring) is applied at the transport
    /// boundary so callers don't see noise. Empty string = no filter.
    /// The stream finishes when `stopScan()` is called.
    func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral>

    /// Stop any in-flight scan. Idempotent.
    func stopScan() async

    /// Attempt to GATT-connect to a previously-discovered peripheral.
    /// Throws `LooiError.connectionFailed` on iOS-level failure or
    /// `LooiError.peripheralNotFound` if the id isn't retrievable.
    /// Returns once didConnect fires; service discovery has NOT yet run.
    func connect(_ id: UUID) async throws

    /// Cancel a connect attempt or close an active connection. Idempotent.
    func disconnect() async

    /// Discover services + characteristics on the currently-connected
    /// peripheral. Returns once both stages are complete (or the timeout
    /// hits). Throws on disconnect mid-discovery.
    func discoverServicesAndCharacteristics(timeout: Duration) async throws

    /// Send `data` to `characteristic`. Throws if the char isn't discovered
    /// (`LooiError.characteristicMissing`) or the write fails
    /// (`LooiError.writeFailed`).
    func write(_ data: Data, to characteristic: CBUUID, type: WriteType) async throws

    /// Synchronous read of `characteristic`. Throws on missing/failure.
    func read(from characteristic: CBUUID) async throws -> Data

    /// Subscribe to notifications/indications for `characteristic`. The
    /// returned stream finishes on disconnect or explicit unsubscribe.
    func subscribe(to characteristic: CBUUID) async throws -> AsyncStream<Data>

    /// Stream of disconnection events (clean or error). Useful for callers
    /// (LooiSession) that need to react without polling.
    var disconnections: AsyncStream<DisconnectionReason> { get }
}

// MARK: - BLERadioState

public enum BLERadioState: Sendable {
    case unknown
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

/// Explicit nonisolated Equatable — avoids MainActor-isolated synthesized
/// conformance (target has defaultIsolation = MainActor).
extension BLERadioState: Equatable {
    public nonisolated static func == (lhs: BLERadioState, rhs: BLERadioState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown): return true
        case (.unsupported, .unsupported): return true
        case (.unauthorized, .unauthorized): return true
        case (.poweredOff, .poweredOff): return true
        case (.poweredOn, .poweredOn): return true
        default: return false
        }
    }
}

// MARK: - DisconnectionReason

public enum DisconnectionReason: Sendable {
    case clean
    case error(String)  // Error's localizedDescription — Sendable
}

/// Explicit nonisolated Equatable — avoids MainActor-isolated synthesized
/// conformance (target has defaultIsolation = MainActor).
extension DisconnectionReason: Equatable {
    public nonisolated static func == (lhs: DisconnectionReason, rhs: DisconnectionReason) -> Bool {
        switch (lhs, rhs) {
        case (.clean, .clean): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
