import Foundation

/// Discrete steps in the FEDA handshake sequence. Carried by
/// `LooiError.handshakeFailed(step:)` so the failure UX can name what
/// stalled. Order matches `HandshakeRunner.run()` (Task 6).
public enum HandshakeStep: Sendable, Equatable {
    case readManufacturer
    case writePhase1
    case subscribeSensors
    case subscribeTelemetry
    case writePhase2
}
