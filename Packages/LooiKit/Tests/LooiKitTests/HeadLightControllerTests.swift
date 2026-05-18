import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

@MainActor
final class HeadLightControllerTests: XCTestCase {

    // MARK: - Head

    func test_lookUp_writesOneLargeStepBelowCenterWithoutResponse() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.lookUp()
        XCTAssertEqual(mock.writes.first?.characteristicUUID, LooiProtocol.Char.head.uuidString)
        XCTAssertEqual(mock.writes.first?.data, Data([0x3A]))
        XCTAssertEqual(mock.writes.first?.type, .withoutResponse)
    }

    func test_lookDown_writesOneLargeStepAboveCenterWithoutResponse() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.lookDown()
        XCTAssertEqual(mock.writes.first?.data, Data([0x7A]))
        XCTAssertEqual(mock.writes.first?.type, .withoutResponse)
    }

    func test_repeatedLookDownStepsTowardBottomRange() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.lookDown()
        try await h.lookDown()
        try await h.lookDown()
        XCTAssertEqual(mock.writes.map(\.data), [Data([0x7A]), Data([0x9A]), Data([0xBA])])
    }

    func test_center_writes0x5AToFED1() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.center()
        XCTAssertEqual(mock.writes.first?.data, Data([0x5A]))
        XCTAssertEqual(mock.writes.first?.type, .withoutResponse)
    }

    // MARK: - Light

    func test_lightFull_writes0x7FToFED2() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 1.0)
        XCTAssertEqual(mock.writes.first?.characteristicUUID, LooiProtocol.Char.light.uuidString)
        XCTAssertEqual(mock.writes.first?.data, Data([0x7F]))
    }

    func test_lightHalf_writesMiddleOfVisibleRange() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 0.5)
        let byte = mock.writes.first!.data.first!
        XCTAssertGreaterThanOrEqual(byte, 63)
        XCTAssertLessThanOrEqual(byte, 64)
    }

    func test_lightOff_writes0x00ToFED2() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.off()
        XCTAssertEqual(mock.writes.first?.data, Data([0x00]))
    }

    func test_lightClampsAboveOne() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 5.0)
        XCTAssertEqual(mock.writes.first?.data, Data([0x7F]))
    }
}
