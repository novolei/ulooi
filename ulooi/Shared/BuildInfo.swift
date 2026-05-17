import Foundation

/// Build identification — displayed as a yellow watermark at the top of the
/// DevTools surface so you can visually verify the deployed build matches the
/// latest commit on disk.
///
/// **MAINTAIN MANUALLY:** update `label` before each `git commit` so the
/// watermark drifts forward with the codebase. The convention is
/// `"<commit-short-hash> — <one-line topic>"`; while a commit is in progress
/// (its hash unknown until after commit), use `"post-<previous-hash>"`.
enum BuildInfo {
    static let label = "post-cf6e931 — Probe v2 (OSLog instrumented + 0-devices probe)"
}
