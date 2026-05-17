import Foundation

/// Discrete steps in the FEDA handshake sequence. Carried by
/// `LooiError.handshakeFailed(step:)` so the failure UX can name what
/// stalled. Order matches `HandshakeRunner.run()` (Task 6).
public enum HandshakeStep: Sendable {
    case readManufacturer
    case writePhase1
    case subscribeSensors
    case subscribeTelemetry
    case writePhase2
}

/// Explicit nonisolated Equatable — avoids MainActor-isolated synthesized
/// conformance (target has defaultIsolation = MainActor).
extension HandshakeStep: Equatable {
    public nonisolated static func == (lhs: HandshakeStep, rhs: HandshakeStep) -> Bool {
        switch (lhs, rhs) {
        case (.readManufacturer, .readManufacturer): return true
        case (.writePhase1, .writePhase1): return true
        case (.subscribeSensors, .subscribeSensors): return true
        case (.subscribeTelemetry, .subscribeTelemetry): return true
        case (.writePhase2, .writePhase2): return true
        default: return false
        }
    }
}
