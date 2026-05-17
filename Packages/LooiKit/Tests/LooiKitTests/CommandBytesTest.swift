import XCTest
@testable import LooiKit

final class CommandBytesTest: XCTestCase {

    // MARK: - Movement (FED0)
    func test_movement_stop_isTwoZeroBytes() {
        XCTAssertEqual(LooiCommand.Movement.stop, Data([0x00, 0x00]))
    }
    func test_movement_forwardMax_speedIs127_turnIsZero() {
        XCTAssertEqual(LooiCommand.Movement.forwardMax, Data([0x7F, 0x00]))
    }
    func test_movement_backwardMax_speedIsNeg127() {
        XCTAssertEqual(LooiCommand.Movement.backwardMax, Data([0x81, 0x00]))
    }
    func test_movement_spinLeftMax_turnIs127() {
        XCTAssertEqual(LooiCommand.Movement.spinLeftMax, Data([0x00, 0x7F]))
    }
    func test_movement_spinRightMax_turnIsNeg127() {
        XCTAssertEqual(LooiCommand.Movement.spinRightMax, Data([0x00, 0x81]))
    }
    func test_movement_normalized_clampsAboveOne() {
        XCTAssertEqual(LooiCommand.Movement.normalized(forward: 5.0, turn: -5.0),
                       Data([0x7F, 0x81]))
    }

    // MARK: - Head (FED1, pitch)
    func test_head_center_is0x5A() {
        XCTAssertEqual(LooiCommand.Head.center, Data([0x5A]))
    }
    func test_head_lookUp_is0x00() {
        XCTAssertEqual(LooiCommand.Head.lookUp, Data([0x00]))
    }
    func test_head_lookDown_is0xFF() {
        XCTAssertEqual(LooiCommand.Head.lookDown, Data([0xFF]))
    }

    // MARK: - Light (FED2)
    func test_light_off_is0x00() {
        XCTAssertEqual(LooiCommand.Light.off, Data([0x00]))
    }

    // MARK: - Handshake (FEDA)
    func test_handshake_phase1_is0x01() {
        XCTAssertEqual(LooiProtocol.Handshake.phase1Data, Data([0x01]))
    }
    func test_handshake_phase2_is0x03() {
        XCTAssertEqual(LooiProtocol.Handshake.phase2Data, Data([0x03]))
    }
}
