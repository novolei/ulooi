import Foundation

/// Test clock that advances on demand. Not full Clock conformance —
/// just a simple counter for asserting "after N attempts, elapsed = X".
public final class FakeClock: Sendable {
    // nonisolated(unsafe) because the default isolation for this target is
    // @MainActor, but FakeClock needs to be directly mutable in nonisolated
    // test helpers. All mutations should happen on @MainActor or under
    // external synchronisation.
    nonisolated(unsafe) private var _now: Duration = .zero

    public var now: Duration { _now }

    public init() {}

    public func advance(by d: Duration) { _now = _now + d }
}
