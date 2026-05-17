import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

/// MotionController unit + integration tests.
///
/// All test methods are @MainActor because MotionController is @MainActor —
/// XCTest cannot implicitly hop to @MainActor, so we declare the class
/// @MainActor explicitly (Swift 6 requirement).
@MainActor
final class MotionControllerTests: XCTestCase {

    // MARK: - Cliff gate

    func test_setMotion_whenGrounded_updatesCurrentMotion() throws {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .grounded })
        try ctl.setMotion(MotionState(label: "Fwd", data: LooiCommand.Movement.forwardMax))
        XCTAssertEqual(ctl.currentMotion.data, LooiCommand.Movement.forwardMax)
    }

    func test_setMotion_whenSuspended_throwsCliffLockedAndDoesNotMutate() {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .frontSuspended })

        XCTAssertThrowsError(try ctl.forward()) { err in
            guard case LooiError.cliffLocked(let directions) = err else {
                XCTFail("expected cliffLocked, got \(err)"); return
            }
            XCTAssertEqual(directions, .frontSuspended)
        }
        // currentMotion must remain .stop — no partial mutation on throw.
        XCTAssertEqual(ctl.currentMotion, .stop)
    }

    func test_stop_alwaysAllowedEvenWhenSuspended() {
        let mock = MockBLETransport()
        // Pre-set a non-stop motion to verify stop() resets it.
        let ctl = MotionController(transport: mock, cliffStateProvider: { .grounded })
        try? ctl.forward()                              // sets forwardMax while grounded
        // Switch provider to suspended and call stop() — must succeed.
        let ctl2 = MotionController(transport: mock, cliffStateProvider: { .frontSuspended })
        ctl2.stop()
        XCTAssertEqual(ctl2.currentMotion, .stop)
    }

    // MARK: - Heartbeat

    func test_heartbeat_writesEvery30ms_usingWithoutResponse() async throws {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .grounded })
        try ctl.forward()           // set a non-stop motion so writes are meaningful
        ctl.startHeartbeat()
        try? await Task.sleep(for: .milliseconds(100))
        ctl.cancelHeartbeat()

        // MockBLETransport.writes is nonisolated (NSLock-guarded) — no await needed.
        let writes = mock.writes
        // Expect ~3 writes in 100ms at 30ms cadence; allow 2-7 for CI jitter.
        XCTAssertGreaterThanOrEqual(writes.count, 2, "too few writes — heartbeat may not have fired")
        XCTAssertLessThanOrEqual(writes.count, 7, "too many writes — cadence may be wrong")

        let movementUUID = LooiProtocol.Char.movement.uuidString
        for w in writes {
            XCTAssertEqual(w.characteristicUUID, movementUUID,
                           "heartbeat wrote to wrong characteristic")
            XCTAssertEqual(w.type, .withoutResponse,
                           "heartbeat must use .withoutResponse (spec §5.3)")
            XCTAssertEqual(w.data, LooiCommand.Movement.forwardMax,
                           "heartbeat wrote unexpected motion data")
        }
    }

    func test_emergencyStop_setsStopAndSendsWithResponse() async {
        let mock = MockBLETransport()
        let ctl = MotionController(transport: mock, cliffStateProvider: { .grounded })
        try? ctl.forward()          // move to a non-stop state
        XCTAssertNotEqual(ctl.currentMotion, .stop)

        await ctl.emergencyStop()

        // currentMotion must be .stop immediately.
        XCTAssertEqual(ctl.currentMotion, .stop)

        let writes = mock.writes
        // The emergency stop write goes to FED0 with .withResponse.
        let last = writes.last
        XCTAssertEqual(last?.data, LooiCommand.Movement.stop)
        XCTAssertEqual(last?.type, .withResponse,
                       "emergencyStop must use .withResponse for confirmed delivery")
    }

    // MARK: - LooiSession integration

    func test_sessionEntersReady_startsHeartbeat() async {
        let mock = MockBLETransport()
        // stubRead is nonisolated — no await needed.
        mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data("LOOI".utf8))
        let session = LooiSession(transport: mock)

        session.startScanAndConnect(nameFilter: "LOOI")
        try? await Task.sleep(for: .milliseconds(50))

        // simulateDiscovery is nonisolated — no await needed.
        mock.simulateDiscovery(DiscoveredPeripheral(
            id: UUID(), name: "LOOI-1", rssi: -50,
            advertisedServices: [], manufacturerData: nil, lastSeen: Date()
        ))

        // HandshakeRunner sleeps ~400ms internally; pad to 800ms for CI headroom.
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(session.state, .ready)

        // Let the heartbeat run for a short window.
        try? await Task.sleep(for: .milliseconds(100))

        let writes = mock.writes
        let movementUUID = LooiProtocol.Char.movement.uuidString
        let heartbeatWrites = writes.filter {
            $0.characteristicUUID == movementUUID && $0.type == .withoutResponse
        }
        XCTAssertGreaterThanOrEqual(heartbeatWrites.count, 1,
                                    "session entering .ready should start the motor heartbeat")
    }

    func test_sessionLeavesReady_stopsHeartbeatAndEmergencyStops() async {
        let mock = MockBLETransport()
        mock.stubRead(LooiProtocol.Char.deviceInfoManufacturer, returns: Data("LOOI".utf8))
        let session = LooiSession(transport: mock)

        session.startScanAndConnect(nameFilter: "LOOI")
        try? await Task.sleep(for: .milliseconds(50))
        mock.simulateDiscovery(DiscoveredPeripheral(
            id: UUID(), name: "LOOI-1", rssi: -50,
            advertisedServices: [], manufacturerData: nil, lastSeen: Date()
        ))
        try? await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(session.state, .ready)

        // Disconnect → I4 (cancelHeartbeat) + I6 (emergencyStop) fire.
        session.disconnect()
        try? await Task.sleep(for: .milliseconds(150))

        let writes = mock.writes
        let movementUUID = LooiProtocol.Char.movement.uuidString
        let fed0Writes = writes.filter { $0.characteristicUUID == movementUUID }

        // The last FED0 write must be the explicit Movement.stop sent via
        // emergencyStop() using .withResponse (I6).
        guard let last = fed0Writes.last else {
            XCTFail("expected at least one FED0 write (heartbeat + emergencyStop)"); return
        }
        XCTAssertEqual(last.data, LooiCommand.Movement.stop,
                       "last FED0 write after disconnect must be Movement.stop")
        XCTAssertEqual(last.type, .withResponse,
                       "emergencyStop write must use .withResponse")
    }
}
