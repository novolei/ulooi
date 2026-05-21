import Foundation
import OSLog

/// Pure-Swift state machine. Owns the current SessionState; rejects
/// invalid transitions; emits a single notification per accepted
/// transition (satisfies invariant I1 + I5 from spec §5.4).
///
/// Designed to be embedded in LooiSession (@MainActor); the machine
/// itself is @MainActor by default isolation.
public final class SessionStateMachine {

    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.session")

    public private(set) var state: SessionState = .disconnected
    public var onTransition: ((SessionState, SessionState) -> Void)?

    public init() {}

    /// Attempt to transition to `target`. Throws `.invalidTransition` if
    /// the move isn't allowed from `state`. On success, logs once and
    /// fires `onTransition` exactly once (I5).
    @discardableResult
    public func transition(to target: SessionState) throws -> SessionState {
        guard isValid(from: state, to: target) else {
            throw TransitionError.invalidTransition(from: state, to: target)
        }
        let previous = state
        state = target
        logger.info("state: \(previous.description, privacy: .public) → \(target.description, privacy: .public)")
        onTransition?(previous, target)
        return state
    }

    /// Force a transition without validation. Use sparingly — only for
    /// emergency reset paths (e.g., app willTerminate forces .disconnected
    /// regardless of source).
    public func forceTransition(to target: SessionState, reason: String) {
        let previous = state
        state = target
        logger.warning("state (forced, \(reason, privacy: .public)): \(previous.description, privacy: .public) → \(target.description, privacy: .public)")
        onTransition?(previous, target)
    }

    public enum TransitionError: Error, Equatable {
        case invalidTransition(from: SessionState, to: SessionState)
    }

    /// Validation table per spec §5.2. Cliff transitions and lifecycle
    /// stops do NOT change SessionState — they're orthogonal.
    private func isValid(from: SessionState, to: SessionState) -> Bool {
        switch (from, to) {
        // From .disconnected
        case (.disconnected, .scanning):       return true
        case (.disconnected, .reconnecting):   return true

        // From .scanning
        case (.scanning, .connecting):         return true
        case (.scanning, .disconnected):       return true
        case (.scanning, .reconnecting):       return true

        // From .connecting
        case (.connecting, .discovering):      return true
        case (.connecting, .disconnected):     return true
        case (.connecting, .reconnecting):     return true

        // From .discovering
        case (.discovering, .handshaking):     return true
        case (.discovering, .disconnected):    return true
        case (.discovering, .reconnecting):    return true

        // From .handshaking
        case (.handshaking, .ready):           return true
        case (.handshaking, .disconnected):    return true
        case (.handshaking, .reconnecting):    return true

        // From .ready
        case (.ready, .reconnecting):          return true
        case (.ready, .disconnected):          return true

        // From .reconnecting
        case (.reconnecting, .scanning):       return true
        case (.reconnecting, .reconnecting):   return true
        case (.reconnecting, .disconnected):   return true

        default:                               return false
        }
    }
}
