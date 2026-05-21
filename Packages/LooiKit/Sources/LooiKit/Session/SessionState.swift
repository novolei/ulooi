import Foundation

/// The nine states a LooiSession passes through. Matches spec §5.2's
/// state diagram. Transitions are validated by SessionStateMachine.
///
/// Declared without explicit protocol conformances here; conformances
/// are in a `nonisolated` extension below so they remain usable in
/// nonisolated contexts under the package's `.defaultIsolation(MainActor.self)`
/// setting (Swift 6 isolated-conformances rule).
public enum SessionState: Sendable, CustomStringConvertible {
    case disconnected
    case scanning
    case connecting
    case discovering
    case handshaking
    case ready
    case reconnecting(attempt: Int)

    public nonisolated var description: String {
        switch self {
        case .disconnected:               return "disconnected"
        case .scanning:                   return "scanning"
        case .connecting:                 return "connecting"
        case .discovering:                return "discovering"
        case .handshaking:                return "handshaking"
        case .ready:                      return "ready"
        case .reconnecting(let attempt):  return "reconnecting(\(attempt))"
        }
    }

    /// Convenience used by lifecycle hooks (heartbeat starts/stops here).
    public nonisolated var isReady: Bool { if case .ready = self { return true }; return false }

    /// True if motor heartbeat + battery poll should be running.
    public nonisolated var hasActiveSession: Bool { isReady }

    /// True if the state represents an "in-progress" attempt (not idle).
    public nonisolated var isInProgress: Bool {
        switch self {
        case .disconnected, .ready: return false
        default: return true
        }
    }
}

// nonisolated conformances so SessionState can be used in nonisolated contexts
// (equality checks, switch statements in non-@MainActor code) despite the
// package target's `.defaultIsolation(MainActor.self)` setting.
nonisolated extension SessionState: Equatable {}
nonisolated extension SessionState: Hashable {}
