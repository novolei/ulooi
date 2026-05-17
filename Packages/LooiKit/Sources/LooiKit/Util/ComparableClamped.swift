import Foundation

/// Clamp a Comparable value into a closed range. Used by `LooiCommand.Movement.normalized`
/// and any other code that needs to bound a normalized input.
extension Comparable {
    public nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
