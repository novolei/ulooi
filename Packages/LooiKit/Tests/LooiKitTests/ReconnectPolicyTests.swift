import XCTest
@testable import LooiKit
import LooiKitTesting

final class ReconnectPolicyTests: XCTestCase {

    func test_defaultSchedule_firstAttemptDelay1s() {
        XCTAssertEqual(ReconnectPolicy.default.delay(forAttempt: 1), .seconds(1))
    }

    func test_defaultSchedule_sequenceDoubles() {
        let p = ReconnectPolicy.default
        // Cumulative check: sum of delays for attempts 1..n must not exceed totalWindow.
        // 1=1, 1+2=3, 1+2+4=7, 1+2+4+8=15, 1+2+4+8+16=31 — all ≤ 60s.
        XCTAssertEqual(p.delay(forAttempt: 1), .seconds(1))
        XCTAssertEqual(p.delay(forAttempt: 2), .seconds(2))
        XCTAssertEqual(p.delay(forAttempt: 3), .seconds(4))
        XCTAssertEqual(p.delay(forAttempt: 4), .seconds(8))
        XCTAssertEqual(p.delay(forAttempt: 5), .seconds(16))
    }

    func test_beyondSchedule_capsAt30s() {
        // Attempt 6: cumulative 1+2+4+8+16+30 = 61s > 60s window → nil (exhausted).
        // Attempt 7 would also cap to 30 but we never get there.
        XCTAssertNil(ReconnectPolicy.default.delay(forAttempt: 6))
        XCTAssertNil(ReconnectPolicy.default.delay(forAttempt: 7))
    }

    func test_elapsedAfter4Attempts_is15s() {
        // 1+2+4+8 = 15s
        XCTAssertEqual(ReconnectPolicy.default.elapsedAfter(attempts: 4), .seconds(15))
    }

    func test_zeroOrNegativeAttempt_returnsNil() {
        XCTAssertNil(ReconnectPolicy.default.delay(forAttempt: 0))
        XCTAssertNil(ReconnectPolicy.default.delay(forAttempt: -1))
    }

    func test_customWindow_truncatesEarly() {
        let p = ReconnectPolicy(totalWindow: .seconds(5), schedule: [.seconds(1), .seconds(2), .seconds(4)])
        XCTAssertEqual(p.delay(forAttempt: 1), .seconds(1))
        XCTAssertEqual(p.delay(forAttempt: 2), .seconds(2))
        // 1+2+4 = 7 > 5 → nil
        XCTAssertNil(p.delay(forAttempt: 3))
    }
}
