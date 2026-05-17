import Foundation

/// Whether a GATT write should request an ack (`.withResponse`) or fire-and-
/// forget (`.withoutResponse`). Motor heartbeat uses `.withoutResponse` —
/// Looi treats `.withResponse` writes to FED0 as keep-alive only and does
/// not act on them (M0.5 finding).
public enum WriteType: Sendable {
    case withResponse
    case withoutResponse
}

// Explicit nonisolated Equatable conformance avoids MainActor-isolation
// (the target has defaultIsolation = MainActor, which would make a synthesized
// conformance MainActor-isolated and unusable in nonisolated contexts).
extension WriteType: Equatable {
    public nonisolated static func == (lhs: WriteType, rhs: WriteType) -> Bool {
        switch (lhs, rhs) {
        case (.withResponse, .withResponse): return true
        case (.withoutResponse, .withoutResponse): return true
        default: return false
        }
    }
}
