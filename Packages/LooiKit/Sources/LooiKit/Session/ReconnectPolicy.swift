import Foundation

/// Pure-Swift backoff schedule for .reconnecting. Spec §5.2:
/// 1s → 2s → 4s → 8s → 16s → 30s → 30s..., capped at 60s total window.
///
/// nonisolated on every member so this struct is callable from any isolation
/// domain (the LooiKit target has defaultIsolation(MainActor.self), but
/// ReconnectPolicy is pure value-type math with no mutable state).
public struct ReconnectPolicy: Sendable {

    public let totalWindow: Duration
    public let schedule: [Duration]

    public nonisolated static let `default` = ReconnectPolicy(
        totalWindow: .seconds(60),
        schedule: [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
    )

    public nonisolated init(totalWindow: Duration, schedule: [Duration]) {
        self.totalWindow = totalWindow
        self.schedule = schedule
    }

    /// Delay before attempt `n` (1-indexed). Past the schedule length,
    /// repeats the last value. Returns nil if:
    ///   - n <= 0 (invalid)
    ///   - the cumulative elapsed time after `n` delays would exceed totalWindow
    ///
    /// nonisolated: pure computation, no mutable state — safe to call from
    /// any isolation domain despite the package's defaultIsolation(MainActor.self).
    public nonisolated func delay(forAttempt n: Int) -> Duration? {
        guard n >= 1, !schedule.isEmpty else { return nil }
        // Compute cumulative elapsed after n delays to check against totalWindow.
        var elapsed: Duration = .zero
        for i in 0..<n {
            let step = i < schedule.count ? schedule[i] : schedule.last!
            elapsed = elapsed + step
        }
        if elapsed > totalWindow { return nil }
        let idx = min(n - 1, schedule.count - 1)
        return schedule[idx]
    }

    /// Total elapsed time after `n` attempts (1-indexed, inclusive).
    ///
    /// nonisolated: pure computation — safe to call from any isolation domain.
    public nonisolated func elapsedAfter(attempts n: Int) -> Duration {
        guard n >= 1, !schedule.isEmpty else { return .zero }
        var elapsed: Duration = .zero
        for i in 0..<n {
            elapsed = elapsed + (i < schedule.count ? schedule[i] : schedule.last!)
        }
        return elapsed
    }
}
