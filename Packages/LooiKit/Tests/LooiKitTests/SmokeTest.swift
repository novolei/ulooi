import XCTest
@testable import LooiKit
import LooiKitTesting

final class SmokeTest: XCTestCase {
    func test_packageVersion_isNonEmpty() {
        XCTAssertFalse(LooiKit.version.isEmpty)
        XCTAssertEqual(LooiKitTesting.version, LooiKit.version)
    }
}
