import Foundation
@preconcurrency import CoreBluetooth
import LooiKit

/// In-memory programmable BLETransport for unit tests. Records every write
/// so tests can assert on byte sequences. Lets tests push discoveries,
/// notifications, and disconnects on demand.
///
/// Implemented as `final class @unchecked Sendable` (same pattern as
/// `CoreBluetoothTransport`) rather than `actor` — CBUUID is not Sendable
/// under Swift 6 strict mode, so actor methods accepting CBUUID params fail
/// the "non-Sendable cannot cross actor boundary" check at the protocol
/// conformance site. NSLock guards all mutable state.
///
/// All BLETransport-conformance methods are marked `nonisolated` so that
/// callers from any isolation domain (including nonisolated XCTest methods)
/// can invoke them without Swift 6 complaining about CBUUID crossing the
/// MainActor boundary (LooiKitTesting target has defaultIsolation = MainActor).
public final class MockBLETransport: BLETransport, @unchecked Sendable {

    private let lock = NSLock()

    // MARK: - Test-observable state

    /// Every successful `write` call, in order.
    public nonisolated private(set) var writes: [WriteCall] {
        get { lock.withLock { _writes } }
        set { lock.withLock { _writes = newValue } }
    }
    private var _writes: [WriteCall] = []

    /// Every characteristic subscribed to, in order (as uuidString).
    public nonisolated private(set) var subscriptions: [String] {
        get { lock.withLock { _subscriptions } }
        set { lock.withLock { _subscriptions = newValue } }
    }
    private var _subscriptions: [String] = []

    /// Every `read(from:)` call, in order (as uuidString).
    public nonisolated private(set) var reads: [String] {
        get { lock.withLock { _reads } }
        set { lock.withLock { _reads = newValue } }
    }
    private var _reads: [String] = []

    /// A recorded write. Stores `characteristicUUID` as a `String` so the struct
    /// is `Sendable` (CBUUID is not Sendable in Swift 6 strict mode).
    public struct WriteCall: Sendable {
        public let characteristicUUID: String   // CBUUID.uuidString
        public let data: Data
        public let type: WriteType
    }

    // MARK: - Test-controlled inputs

    private var _radioState: BLERadioState = .poweredOn

    public nonisolated var radioState: BLERadioState {
        get async { lock.withLock { _radioState } }
    }

    public nonisolated func setRadioState(_ state: BLERadioState) {
        lock.withLock { _radioState = state }
    }

    /// Pre-program the value `read(from:)` returns (keyed by uuidString).
    private var _readResponses: [String: Data] = [:]

    public nonisolated func stubRead(_ characteristic: CBUUID, returns data: Data) {
        lock.withLock { _readResponses[characteristic.uuidString] = data }
    }

    /// Pre-program failures. If set, the matching call throws instead of
    /// succeeding. Stored as String (uuidString) — CBUUID is not Sendable.
    public enum Failure: Error, Sendable {
        case connectionFailure
        case writeFailure(String)            // CBUUID.uuidString
        case characteristicMissing(String)   // CBUUID.uuidString
    }
    private var _queuedFailures: [Failure] = []

    public nonisolated func queueFailure(_ failure: Failure) {
        lock.withLock { _queuedFailures.append(failure) }
    }

    // MARK: - Streams

    private var _discoveryContinuations: [AsyncStream<DiscoveredPeripheral>.Continuation] = []
    private var _subscriptionContinuations: [String: [AsyncStream<Data>.Continuation]] = [:]
    private var _disconnectionContinuations: [AsyncStream<DisconnectionReason>.Continuation] = []

    public nonisolated func simulateDiscovery(_ p: DiscoveredPeripheral) {
        let conts = lock.withLock { _discoveryContinuations }
        for cont in conts { cont.yield(p) }
    }

    public nonisolated func simulateNotification(on characteristic: CBUUID, data: Data) {
        let conts = lock.withLock { _subscriptionContinuations[characteristic.uuidString] ?? [] }
        for cont in conts { cont.yield(data) }
    }

    public nonisolated func simulateDisconnect(reason: DisconnectionReason = .clean) {
        let conts = lock.withLock { _disconnectionContinuations }
        for cont in conts { cont.yield(reason) }
    }

    // MARK: - BLETransport conformance

    public nonisolated var disconnections: AsyncStream<DisconnectionReason> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            lock.withLock { _disconnectionContinuations.append(continuation) }
        }
    }

    public nonisolated func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            lock.withLock { _discoveryContinuations.append(continuation) }
        }
    }

    public nonisolated func stopScan() async {
        let conts = lock.withLock { () -> [AsyncStream<DiscoveredPeripheral>.Continuation] in
            let c = _discoveryContinuations; _discoveryContinuations.removeAll(); return c
        }
        for cont in conts { cont.finish() }
    }

    public nonisolated func connect(_ id: UUID) async throws {
        let shouldFail = lock.withLock { () -> Bool in
            if case .connectionFailure = _queuedFailures.first {
                _queuedFailures.removeFirst()
                return true
            }
            return false
        }
        if shouldFail {
            // Task 4 adaptation: connectionFailed takes underlyingDescription: String
            throw LooiError.connectionFailed(underlyingDescription: "Mock connection failure")
        }
    }

    public nonisolated func disconnect() async {
        simulateDisconnect(reason: .clean)
    }

    public nonisolated func discoverServicesAndCharacteristics(timeout: Duration) async throws {
        // no-op in mock; tests assume all characteristics exist unless they
        // call queueFailure(.characteristicMissing(...))
    }

    public nonisolated func write(_ data: Data, to characteristic: CBUUID, type: WriteType) async throws {
        let uuidStr = characteristic.uuidString
        // Task 4 adaptation: Failure stores String (uuidString), compare accordingly
        let failure = lock.withLock { () -> Failure? in
            if case let .characteristicMissing(queued) = _queuedFailures.first, queued == uuidStr {
                return _queuedFailures.removeFirst()
            }
            if case let .writeFailure(queued) = _queuedFailures.first, queued == uuidStr {
                return _queuedFailures.removeFirst()
            }
            return nil
        }
        if let failure {
            switch failure {
            case .characteristicMissing:
                // Task 4 adaptation: characteristicMissing takes String (uuidString)
                throw LooiError.characteristicMissing(uuidStr)
            case .writeFailure:
                // Task 4 adaptation: writeFailed takes (String, underlyingDescription: String)
                throw LooiError.writeFailed(uuidStr, underlyingDescription: "Mock write failure")
            default:
                break
            }
        }
        lock.withLock {
            _writes.append(WriteCall(characteristicUUID: uuidStr, data: data, type: type))
        }
    }

    public nonisolated func read(from characteristic: CBUUID) async throws -> Data {
        let uuidStr = characteristic.uuidString
        lock.withLock { _reads.append(uuidStr) }
        return lock.withLock { _readResponses[uuidStr] } ?? Data()
    }

    public nonisolated func subscribe(to characteristic: CBUUID) async throws -> AsyncStream<Data> {
        let uuidStr = characteristic.uuidString
        // Check for a queued failure matching this characteristic
        let failure = lock.withLock { () -> Failure? in
            if case let .characteristicMissing(queued) = _queuedFailures.first, queued == uuidStr {
                return _queuedFailures.removeFirst()
            }
            return nil
        }
        if let failure {
            switch failure {
            case .characteristicMissing:
                throw LooiError.characteristicMissing(uuidStr)
            default:
                break
            }
        }
        lock.withLock { _subscriptions.append(uuidStr) }
        return AsyncStream { [weak self] continuation in
            guard let self else { continuation.finish(); return }
            lock.withLock {
                _subscriptionContinuations[uuidStr, default: []].append(continuation)
            }
        }
    }

    public init() {}
}
