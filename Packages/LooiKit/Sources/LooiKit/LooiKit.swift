import Foundation

/// LooiKit — public Swift Package for the LOOI robot iOS embodiment.
///
/// See `docs/superpowers/specs/2026-05-17-ulooi-m1-foundation-design.md` for
/// the design that drives this package's API surface.
public enum LooiKit {
    /// Package semantic version. Synthesized at compile time from the
    /// containing PR; bumped as part of the M1 ship commit.
    public nonisolated(unsafe) static let version = "0.2.0-dev.m1.pr1"
}
