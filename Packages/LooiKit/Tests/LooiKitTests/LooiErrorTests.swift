import XCTest
import CoreBluetooth
@testable import LooiKit

final class LooiErrorTests: XCTestCase {

    func test_cliffLocked_zhDescription_mentionsHangs() {
        let err = LooiError.cliffLocked(directions: .frontSuspended)
        let desc = err.errorDescription ?? ""
        XCTAssertTrue(desc.contains("悬空"))
    }

    func test_cliffLocked_englishFallback_mentionsSuspended() {
        let err = LooiError.cliffLocked(directions: .frontSuspended)
        XCTAssertTrue(err.englishDescription.contains("suspended"))
    }

    func test_peripheralNotFound_carriesTimeout() {
        let err = LooiError.peripheralNotFound(timeout: .seconds(15))
        XCTAssertTrue(err.errorDescription!.contains("15"))
    }

    func test_handshakeFailed_carriesStep() {
        let err = LooiError.handshakeFailed(step: .writePhase2)
        XCTAssertTrue(err.errorDescription!.contains("writePhase2"))
        XCTAssertTrue(err.englishDescription.contains("writePhase2"))
    }

    func test_characteristicMissing_carriesUUID() {
        // characteristicMissing now takes a UUID string directly (Swift 6: CBUUID is non-Sendable).
        let uuidString = LooiProtocol.Char.handshake.uuidString
        let err = LooiError.characteristicMissing(uuidString)
        XCTAssertTrue(err.errorDescription!.lowercased().contains("feda"))
    }

    func test_cliffState_grounded_isEmpty() {
        XCTAssertTrue(CliffState.grounded.isGrounded)
        XCTAssertFalse(CliffState.grounded.isSuspended)
    }

    func test_cliffState_frontSuspended_isNotGrounded() {
        XCTAssertFalse(CliffState.frontSuspended.isGrounded)
        XCTAssertTrue(CliffState.frontSuspended.isSuspended)
    }
}
