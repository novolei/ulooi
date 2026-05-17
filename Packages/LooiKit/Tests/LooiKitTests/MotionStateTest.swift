import XCTest
@testable import LooiKit

final class MotionStateTest: XCTestCase {
    func test_stop_label_isSTOP() {
        XCTAssertEqual(MotionState.stop.label, "STOP")
    }
    func test_stop_data_isTwoZeroBytes() {
        XCTAssertEqual(MotionState.stop.data, Data([0x00, 0x00]))
    }
    func test_preset_all_includesAllNineEntries() {
        XCTAssertEqual(MotionPreset.all.count, 9)
        XCTAssertEqual(MotionPreset.all.first?.label, "STOP")
    }
}
