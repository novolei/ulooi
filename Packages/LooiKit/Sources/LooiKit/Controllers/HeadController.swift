import Foundation
import OSLog

/// Controls Looi's head pitch via FED1 (1-byte position commands).
///
/// Three named positions: `lookUp` (0x00), `center` (0x5A), `lookDown` (0xFF).
///
/// **M0.5 finding:** `lookDown` (0xFF) auto-springs back to center — the firmware
/// treats it as a "nod" gesture rather than a hold-at-pitch command. `lookUp` (0x00)
/// behavior is symmetric and may do the same. Use `center` for a stable rest position.
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

    /// Tilt head down (0xFF → FED1).
    ///
    /// Empirically observed to auto-spring back to center after firing (M0.5 finding).
    /// Do not expect the head to stay in the down position.
    public func lookDown() async throws {
        logger.debug("head: lookDown (0xFF) — auto-springs back per M0.5")
        try await transport.write(LooiCommand.Head.lookDown, to: LooiProtocol.Char.head, type: .withResponse)
    }

    /// Return head to mechanical center (0x5A → FED1).
    public func center() async throws {
        logger.debug("head: center (0x5A)")
        try await transport.write(LooiCommand.Head.center, to: LooiProtocol.Char.head, type: .withResponse)
    }
}
