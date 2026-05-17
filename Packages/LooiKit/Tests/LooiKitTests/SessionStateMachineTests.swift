import XCTest
@testable import LooiKit

@MainActor
final class SessionStateMachineTests: XCTestCase {

    func test_initialState_isDisconnected() {
        let m = SessionStateMachine()
        XCTAssertEqual(m.state, .disconnected)
    }

    func test_happyPath_scanToReady() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        XCTAssertEqual(m.state, .ready)
    }

    func test_invalidTransition_disconnectedToReady_throws() {
        let m = SessionStateMachine()
        XCTAssertThrowsError(try m.transition(to: .ready)) { err in
            guard case SessionStateMachine.TransitionError.invalidTransition(let from, let to) = err else {
                XCTFail("wrong error: \(err)"); return
            }
            XCTAssertEqual(from, .disconnected)
            XCTAssertEqual(to, .ready)
        }
    }

    func test_readyToReconnecting_thenToScanning() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        try m.transition(to: .reconnecting(attempt: 1))
        try m.transition(to: .scanning)
        XCTAssertEqual(m.state, .scanning)
    }

    func test_reconnecting_canBumpAttempt() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        try m.transition(to: .reconnecting(attempt: 1))
        try m.transition(to: .reconnecting(attempt: 2))
        try m.transition(to: .reconnecting(attempt: 3))
        XCTAssertEqual(m.state, .reconnecting(attempt: 3))
    }

    func test_reconnectingTimeout_returnsToDisconnected() throws {
        let m = SessionStateMachine()
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        try m.transition(to: .discovering)
        try m.transition(to: .handshaking)
        try m.transition(to: .ready)
        try m.transition(to: .reconnecting(attempt: 1))
        try m.transition(to: .disconnected)
        XCTAssertEqual(m.state, .disconnected)
    }

    func test_onTransition_firesOncePerAcceptedTransition() throws {
        let m = SessionStateMachine()
        var events: [(SessionState, SessionState)] = []
        m.onTransition = { from, to in events.append((from, to)) }
        try m.transition(to: .scanning)
        try m.transition(to: .connecting)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].0, .disconnected)
        XCTAssertEqual(events[0].1, .scanning)
        XCTAssertEqual(events[1].0, .scanning)
        XCTAssertEqual(events[1].1, .connecting)
    }

    func test_onTransition_doesNotFireOnRejection() {
        let m = SessionStateMachine()
        var count = 0
        m.onTransition = { _, _ in count += 1 }
        XCTAssertThrowsError(try m.transition(to: .ready))
        XCTAssertEqual(count, 0)
    }

    func test_forceTransition_bypassesValidation() {
        let m = SessionStateMachine()
        m.forceTransition(to: .ready, reason: "test override")
        XCTAssertEqual(m.state, .ready)
    }

    func test_isReady_onlyTrueWhenReady() {
        XCTAssertFalse(SessionState.disconnected.isReady)
        XCTAssertFalse(SessionState.scanning.isReady)
        XCTAssertTrue(SessionState.ready.isReady)
        XCTAssertFalse(SessionState.reconnecting(attempt: 1).isReady)
    }
}
