import Foundation

public enum GestureKind: String, CaseIterable, Identifiable, Sendable {
    case wave
    case lookAtMe
    case sleep

    public var id: String { rawValue }
}
