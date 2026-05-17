import Foundation
import OSLog

/// Controls Looi's headlight via FED2 (1-byte brightness commands).
///
/// M0.5 confirmed an analog brightness gradient (not binary on/off): the full
/// range 0x00…0xFF maps linearly to off…full-bright.
///
/// `set(brightness:)` accepts a normalized Double in [0.0, 1.0] and clamps
/// out-of-range inputs rather than throwing, so callers can pass e.g. a slider
/// value directly without manual clamping.
///
/// Writes use `.withResponse` so delivery is confirmed before the caller proceeds.
///
/// Swift 6: `@MainActor` by package default (`defaultIsolation(MainActor.self)`).
@MainActor
public final class LightController {

    private let transport: BLETransport
    private let logger = Logger(subsystem: "ai.if2.ulooi", category: "looikit.light")

    public init(transport: BLETransport) {
        self.transport = transport
    }

    // MARK: - Brightness control

    /// Set headlight brightness.
    ///
    /// - Parameter brightness: Normalized value in [0.0, 1.0].
    ///   Values outside this range are clamped silently.
    ///   0.0 → off (0x00), 1.0 → full (0xFF).
    public func set(brightness: Double) async throws {
        let clamped = max(0.0, min(1.0, brightness))
        let byte = UInt8(clamped * 255)
        logger.debug("light: set brightness \(brightness, format: .fixed(precision: 2)) → 0x\(String(byte, radix: 16, uppercase: true))")
        try await transport.write(Data([byte]), to: LooiProtocol.Char.light, type: .withResponse)
    }

    /// Turn the headlight off (equivalent to `set(brightness: 0.0)`).
    public func off() async throws {
        try await set(brightness: 0.0)
    }
}
