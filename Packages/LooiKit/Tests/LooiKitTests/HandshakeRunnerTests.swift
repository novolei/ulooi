import XCTest
@preconcurrency import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

final class HandshakeRunnerTests: XCTestCase {

    func test_happyPath_emitsExpectedByteSequence() async throws {
        let mock = MockBLETransport()
        mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data("LOOI".utf8))

        let runner = HandshakeRunner(transport: mock)
        _ = try await runner.run()

        // nonisolated properties — no await needed
        let writes = mock.writes
        let subs = mock.subscriptions
        let reads = mock.reads

        // 1× read on 2A29
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(reads.first, LooiProtocol.Char.deviceInfoManufacturer.uuidString)

        // 2× write to FEDA: 0x01 then 0x03
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].characteristicUUID, LooiProtocol.Char.handshake.uuidString)
        XCTAssertEqual(writes[0].data, Data([0x01]))
        XCTAssertEqual(writes[1].characteristicUUID, LooiProtocol.Char.handshake.uuidString)
        XCTAssertEqual(writes[1].data, Data([0x03]))

        // 2× subscribe: FED5 first, FED9 second
        XCTAssertEqual(subs, [
            LooiProtocol.Char.sensors.uuidString,
            LooiProtocol.Char.telemetry.uuidString,
        ])
    }

    func test_phase1WriteFailure_throwsHandshakeFailedWritePhase1() async {
        let mock = MockBLETransport()
        // Queue write failure for FEDA — triggers on the phase1 write
        mock.queueFailure(.writeFailure(LooiProtocol.Char.handshake.uuidString))
        let runner = HandshakeRunner(transport: mock)
        do {
            _ = try await runner.run()
            XCTFail("expected throw")
        } catch let LooiError.handshakeFailed(step) {
            XCTAssertEqual(step, .writePhase1)
        } catch {
            XCTFail("expected LooiError.handshakeFailed(.writePhase1), got \(error)")
        }
    }

    func test_subscribeSensorsFailure_throwsHandshakeFailedSubscribeSensors() async {
        let mock = MockBLETransport()
        // Queue missing characteristic for FED5 — triggers on the sensors subscribe
        mock.queueFailure(.characteristicMissing(LooiProtocol.Char.sensors.uuidString))
        let runner = HandshakeRunner(transport: mock)
        do {
            _ = try await runner.run()
            XCTFail("expected throw")
        } catch let LooiError.handshakeFailed(step) {
            XCTAssertEqual(step, .subscribeSensors)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_manufacturerReadFailure_isNonFatal() async throws {
        // 2A29 read failure should NOT abort; handshake continues.
        // MockBLETransport.read does not check queuedFailures — so we queue
        // a characteristicMissing for 2A29 on the write path won't match.
        // Instead we verify the non-fatal behaviour by subclassing via
        // a thin wrapper that throws on read and delegates everything else.
        let mock = FailingReadMockTransport()
        let runner = HandshakeRunner(transport: mock)
        _ = try await runner.run()  // does not throw
        let writes = mock.writes
        XCTAssertEqual(writes.count, 2)  // phase1 + phase2 still happened
    }
}

// MARK: - Helper: transport that always fails read(from:)

/// Wraps MockBLETransport and overrides read(from:) to always throw
/// LooiError.characteristicMissing so we can test the non-fatal branch
/// without mutating MockBLETransport's queued-failure mechanism (which is
/// consumed by write, not read).
///
/// `@preconcurrency` suppresses Swift 6 Sendability warnings on CBUUID
/// parameters — same pattern used by MockBLETransport in LooiKitTesting.
@preconcurrency
private final class FailingReadMockTransport: BLETransport, @unchecked Sendable {
    private let inner = MockBLETransport()

    nonisolated var writes: [MockBLETransport.WriteCall] { inner.writes }

    nonisolated var radioState: BLERadioState {
        get async { await inner.radioState }
    }

    nonisolated func scan(nameFilter: String) -> AsyncStream<DiscoveredPeripheral> {
        inner.scan(nameFilter: nameFilter)
    }

    nonisolated func stopScan() async { await inner.stopScan() }

    nonisolated func connect(_ id: UUID) async throws { try await inner.connect(id) }

    nonisolated func disconnect() async { await inner.disconnect() }

    nonisolated func discoverServicesAndCharacteristics(timeout: Duration) async throws {
        try await inner.discoverServicesAndCharacteristics(timeout: timeout)
    }

    nonisolated func write(_ data: Data, to characteristic: CBUUID, type: WriteType) async throws {
        try await inner.write(data, to: characteristic, type: type)
    }

    /// Always throws — simulates 2A29 not present on device.
    nonisolated func read(from characteristic: CBUUID) async throws -> Data {
        throw LooiError.characteristicMissing(characteristic.uuidString)
    }

    nonisolated func subscribe(to characteristic: CBUUID) async throws -> AsyncStream<Data> {
        try await inner.subscribe(to: characteristic)
    }

    nonisolated var disconnections: AsyncStream<DisconnectionReason> { inner.disconnections }
}
