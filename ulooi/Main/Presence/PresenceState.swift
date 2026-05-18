import Foundation
import LooiKit

enum PresenceState: Equatable {
    case booting
    case lookingForBody
    case awake
    case idle
    case touched
    case performingGesture(GestureKind)
    case suspended
    case sleeping
    case disconnected
    case errorRecoverable(String)

    static func derive(
        sessionState: SessionState,
        cliffState: CliffState,
        lastTouchDate: Date?,
        now: Date,
        sleeping: Bool,
        activeGesture: GestureKind?
    ) -> PresenceState {
        if let activeGesture { return .performingGesture(activeGesture) }
        if sleeping { return .sleeping }
        if cliffState.isSuspended { return .suspended }
        if let lastTouchDate, now.timeIntervalSince(lastTouchDate) < 1.2 { return .touched }

        switch sessionState {
        case .disconnected:
            return .disconnected
        case .scanning, .connecting, .discovering, .handshaking, .reconnecting:
            return .lookingForBody
        case .ready:
            return .idle
        }
    }
}
