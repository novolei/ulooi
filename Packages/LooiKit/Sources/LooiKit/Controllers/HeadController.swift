import Foundation
import OSLog

/// Controls Looi's head pitch via FED1 (1-byte position commands).
///
/// novolei/LOOI-Robot uses an in-memory `head_pos` starting at 0x5A, increments
/// by 10 for head-up, decrements by 10 for head-down, and writes with
/// `response=False`. This controller mirrors that contract.
///
/// Writes use `.withoutResponse` to match the working Python implementation.
///
/// Swift 6: `@MainActor` by package default (`defaultIsolation(MainActor.self)`).
@MainActor
public final class HeadController {

    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.head")
    private var currentPosition: UInt8 = 0x5A
    private static let step = 10

    public init(transport: BLETransport) {
        self.transport = transport
    }

    // MARK: - Named positions

    /// Tilt head up one step from the current tracked position.
    public func lookUp() async throws {
        let next = min(0xFF, Int(currentPosition) + Self.step)
        try await setPosition(UInt8(next))
    }

    /// Tilt head down one step from the current tracked position.
    public func lookDown() async throws {
        let next = max(0x00, Int(currentPosition) - Self.step)
        try await setPosition(UInt8(next))
    }

    /// Return head to mechanical center (0x5A -> FED1).
    public func center() async throws {
        try await setPosition(0x5A)
    }

    /// Set a raw FED1 pitch position and remember it for future step commands.
    public func setPosition(_ position: UInt8) async throws {
        currentPosition = position
        logger.debug("head: set position 0x\(String(position, radix: 16, uppercase: true))")
        try await transport.write(Data([position]), to: LooiProtocol.Char.head, type: .withoutResponse)
    }
}
