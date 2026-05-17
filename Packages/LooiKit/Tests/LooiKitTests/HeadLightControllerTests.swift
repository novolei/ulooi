import XCTest
import CoreBluetooth
@testable import LooiKit
import LooiKitTesting

@MainActor
final class HeadLightControllerTests: XCTestCase {

    // MARK: - Head

    func test_lookUp_writes0x00ToFED1() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.lookUp()
        XCTAssertEqual(mock.writes.first?.characteristicUUID, LooiProtocol.Char.head.uuidString)
        XCTAssertEqual(mock.writes.first?.data, Data([0x00]))
    }

    func test_lookDown_writes0xFFToFED1() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.lookDown()
        XCTAssertEqual(mock.writes.first?.data, Data([0xFF]))
    }

    func test_center_writes0x5AToFED1() async throws {
        let mock = MockBLETransport()
        let h = HeadController(transport: mock)
        try await h.center()
        XCTAssertEqual(mock.writes.first?.data, Data([0x5A]))
    }

    // MARK: - Light

    func test_lightFull_writes0xFFToFED2() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 1.0)
        XCTAssertEqual(mock.writes.first?.characteristicUUID, LooiProtocol.Char.light.uuidString)
        XCTAssertEqual(mock.writes.first?.data, Data([0xFF]))
    }

    func test_lightHalf_writesApprox128ToFED2() async throws {
        let mock = MockBLETransport()
        let l = LightController(transport: mock)
        try await l.set(brightness: 0.5)
        let byte = mock.writes.first!.data.first!
        XCTAssertGreaterThanOrEqual(byte, 126)
        XCTAssertLessThanOrEqual(byte, 128)
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
        XCTAssertEqual(mock.writes.first?.data, Data([0xFF]))
    }
}
