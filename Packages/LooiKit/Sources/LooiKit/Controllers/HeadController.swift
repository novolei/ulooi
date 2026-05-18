import Foundation
import OSLog

/// Controls Looi's head pitch via FED1 (1-byte position commands).
///
/// Three named positions: `lookUp` (0x00), `center` (0x5A), `lookDown` (0xB0).
///
/// **M0.5 finding:** `0xFF` auto-springs back to center — the firmware treats it
/// as a "nod" gesture rather than a hold-at-pitch command. `lookDown()` therefore
/// uses a non-extreme down pitch; use `nodDown()` when the auto-return gesture is
/// desired.
///
/// Writes use `.withResponse` so delivery is confirmed before the caller proceeds.
///
/// Swift 6: `@MainActor` by package default (`defaultIsolation(MainActor.self)`).
@MainActor
public final class HeadController {

    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.head")

    public init(transport: BLETransport) {
        self.transport = transport
    }

    // MARK: - Named positions

    /// Tilt head up (0x00 → FED1). May auto-spring back per M0.5.
    public func lookUp() async throws {
        logger.debug("head: lookUp (0x00)")
        try await transport.write(LooiCommand.Head.lookUp, to: LooiProtocol.Char.head, type: .withResponse)
    }

    /// Tilt head down with a non-extreme hold position (0xB0 → FED1).
    public func lookDown() async throws {
        logger.debug("head: lookDown hold (0xB0)")
        try await transport.write(LooiCommand.Head.lookDown, to: LooiProtocol.Char.head, type: .withResponse)
    }

    /// Dip down and auto-return to center (0xFF → FED1).
    public func nodDown() async throws {
        logger.debug("head: nodDown (0xFF) — auto-springs back per M0.5")
        try await transport.write(LooiCommand.Head.nodDown, to: LooiProtocol.Char.head, type: .withResponse)
    }

    /// Return head to mechanical center (0x5A → FED1).
    public func center() async throws {
        logger.debug("head: center (0x5A)")
        try await transport.write(LooiCommand.Head.center, to: LooiProtocol.Char.head, type: .withResponse)
    }
}
