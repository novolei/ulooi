import Foundation

public enum GestureKind: String, CaseIterable, Identifiable, Sendable {
    case wave
    case lookAtMe
    case sleep

    public nonisolated var id: String { rawValue }
}
