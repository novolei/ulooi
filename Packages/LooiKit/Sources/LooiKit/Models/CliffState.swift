import Foundation

/// 4-direction cliff sensor state. M0.5 confirmed: bit 0 (front) toggles
/// when Looi's front wheels lift. Full 4-direction mapping is opportunistic
/// during M1 development (spec §3 out-of-scope until M2 if needed) but the
/// type is shaped for that future. Decoded from FED9 type 0x01 packets.
public struct CliffState: Sendable, Equatable, OptionSet {
    public let rawValue: UInt8

    public nonisolated static let frontSuspended = CliffState(rawValue: 1 << 0)
    public nonisolated static let rearSuspended  = CliffState(rawValue: 1 << 1)
    public nonisolated static let leftSuspended  = CliffState(rawValue: 1 << 2)
    public nonisolated static let rightSuspended = CliffState(rawValue: 1 << 3)

    public nonisolated static let grounded: CliffState = []

    public nonisolated init(rawValue: UInt8) { self.rawValue = rawValue }

    /// True when ALL wheels are on the ground (motor commands allowed).
    public nonisolated var isGrounded: Bool { rawValue == 0 }

    /// True when any wheel is suspended (motor commands hard-blocked).
    public nonisolated var isSuspended: Bool { rawValue != 0 }
}
