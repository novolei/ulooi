import Foundation
import LooiKit
import OSLog

/// Triple-channel instrumentation. Each event writes to:
///   1. **OSLog** — Apple system-level facility. Visible in Xcode console and
///      `Console.app` via `subsystem == "ai.if2.ulooi"`. Persistent, queryable,
///      independent of SwiftUI / Observation / our ProbeLog code. PRIMARY.
///   2. **print()** — Plain stdout. Visible in Xcode console with `[ulooi]`
///      prefix. Backup verification if OSLog filtering misbehaves.
///   3. **ProbeLog.shared** — Existing in-app Logs tab display.
///
/// Use this everywhere a probe event happens instead of calling
/// `ProbeLog.shared.info` / `.warn` / `.error` / `.bytes` directly. The triple
/// channel makes verification robust to single-channel failures.
///
/// Filter Xcode console with: `[ulooi]` substring.
/// Filter Console.app with: subsystem == "ai.if2.ulooi"
enum DevLog {
    // Category-specific loggers — match by category in Console.app.
    // `nonisolated` because: (1) `Logger` is `Sendable`; (2) the project sets
    // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` which would otherwise make
    // these implicitly @MainActor, blocking their use as default parameter
    // values (`channel: Logger = probe` evaluates at the call site, which may
    // be a `nonisolated` context like a CB delegate). Same pattern as
    // `BLECentral.translate(_:)` (see cb1c7a9).
    nonisolated static let ble = Logger(subsystem: "ai.if2.ulooi", category: "ble")
    nonisolated static let ui  = Logger(subsystem: "ai.if2.ulooi", category: "ui")
    nonisolated static let probe = Logger(subsystem: "ai.if2.ulooi", category: "probe")

    @MainActor
    static func event(_ message: String, channel: Logger = probe) {
        print("[ulooi] \(message)")
        channel.info("\(message, privacy: .public)")
        ProbeLog.shared.info(message)
    }

    @MainActor
    static func warn(_ message: String, channel: Logger = probe) {
        print("[ulooi WARN] \(message)")
        channel.warning("\(message, privacy: .public)")
        ProbeLog.shared.warn(message)
    }

    @MainActor
    static func error(_ message: String, channel: Logger = probe) {
        print("[ulooi ERR] \(message)")
        channel.error("\(message, privacy: .public)")
        ProbeLog.shared.error(message)
    }

    @MainActor
    static func bytes(_ label: String, _ data: Data, channel: Logger = probe) {
        let hex = data.hexEncoded
        print("[ulooi RAW] \(label): \(hex)")
        channel.info("\(label, privacy: .public): \(hex, privacy: .public)")
        ProbeLog.shared.bytes(label, data)
    }
}
