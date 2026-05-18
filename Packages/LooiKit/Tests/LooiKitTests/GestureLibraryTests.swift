import Foundation
import XCTest
@testable import LooiKit
import LooiKitTesting

@MainActor
final class GestureLibraryTests: XCTestCase {
    func test_sleep_stopsMotionDimsLightAndCentersHead() async throws {
        let mock = MockBLETransport()
        let motion = MotionController(transport: mock, cliffStateProvider: { .grounded })
        let head = HeadController(transport: mock)
        let light = LightController(transport: mock)
        let gestures = GestureLibrary(motion: motion, head: head, light: light)

        try motion.forward()
        try await gestures.perform(.sleep)

        XCTAssertEqual(motion.currentMotion, .stop)
        let writes = mock.writes
        XCTAssertTrue(writes.contains {
            $0.characteristicUUID == LooiProtocol.Char.light.uuidString && $0.data == Data([0x00])
        })
        XCTAssertTrue(writes.contains {
            $0.characteristicUUID == LooiProtocol.Char.head.uuidString && $0.data == LooiCommand.Head.center
        })
    }

    func test_lookAtMe_centersHeadAndSetsWarmLight() async throws {
        let mock = MockBLETransport()
        let gestures = GestureLibrary(
            motion: MotionController(transport: mock, cliffStateProvider: { .grounded }),
            head: HeadController(transport: mock),
            light: LightController(transport: mock)
        )

        try await gestures.perform(.lookAtMe)

        let writes = mock.writes
        XCTAssertTrue(writes.contains {
            $0.characteristicUUID == LooiProtocol.Char.head.uuidString && $0.data == LooiCommand.Head.center
        })
        XCTAssertTrue(writes.contains {
            $0.characteristicUUID == LooiProtocol.Char.light.uuidString && $0.data.count == 1 && $0.data[0] >= 0x80
        })
    }

    func test_wave_usesHeadLightAndReturnsToStop() async throws {
        let mock = MockBLETransport()
        let motion = MotionController(transport: mock, cliffStateProvider: { .grounded })
        let gestures = GestureLibrary(
            motion: motion,
            head: HeadController(transport: mock),
            light: LightController(transport: mock)
        )

        try await gestures.perform(.wave)

        XCTAssertEqual(motion.currentMotion, .stop)
        XCTAssertTrue(mock.writes.contains { $0.characteristicUUID == LooiProtocol.Char.head.uuidString })
        XCTAssertTrue(mock.writes.contains { $0.characteristicUUID == LooiProtocol.Char.light.uuidString })
    }

    func test_waveWhenSuspended_throwsAndDoesNotStartMotion() async {
        let mock = MockBLETransport()
        let motion = MotionController(transport: mock, cliffStateProvider: { .frontSuspended })
        let gestures = GestureLibrary(
            motion: motion,
            head: HeadController(transport: mock),
            light: LightController(transport: mock)
        )

        do {
            try await gestures.perform(.wave)
            XCTFail("Expected wave to throw cliffLocked when suspended")
        } catch LooiError.cliffLocked {
            XCTAssertEqual(motion.currentMotion, .stop)
            XCTAssertFalse(mock.writes.contains { $0.characteristicUUID == LooiProtocol.Char.head.uuidString })
            XCTAssertFalse(mock.writes.contains { $0.characteristicUUID == LooiProtocol.Char.light.uuidString })
        } catch {
            XCTFail("Expected cliffLocked, got \(error)")
        }
    }

    func test_waveWhenSuspendedAfterPriorMotion_throwsAndStopsMotion() async throws {
        let mock = MockBLETransport()
        var cliff: CliffState = .grounded
        let motion = MotionController(transport: mock, cliffStateProvider: { cliff })
        let gestures = GestureLibrary(
            motion: motion,
            head: HeadController(transport: mock),
            light: LightController(transport: mock)
        )

        try motion.forward()
        cliff = .frontSuspended

        do {
            try await gestures.perform(.wave)
            XCTFail("Expected wave to throw cliffLocked when suspended")
        } catch LooiError.cliffLocked {
            XCTAssertEqual(motion.currentMotion, .stop)
        } catch {
            XCTFail("Expected cliffLocked, got \(error)")
        }
    }
}
