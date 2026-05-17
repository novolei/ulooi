import Foundation

/// Build identification — displayed as a yellow watermark at the top of the
/// DevTools surface so you can visually verify the deployed build matches the
/// latest commit on disk.
///
/// **MAINTAIN MANUALLY:** update `label` immediately BEFORE each `git commit`.
/// Format convention (topic-first, anchor-last):
///
///     "<TOPIC> · <YYYY-MM-DD> · newer than <PRIOR-HASH>"
///
/// Verify a deployed build matches the latest commit by mentally matching
/// the displayed label with `git log -1 --oneline` on disk:
///   - Topic words should appear in the commit message subject.
///   - Date should be ≤ today.
///   - "newer than X" anchor should reference a commit you previously deployed.
///
/// Future improvement: replace this manual scheme with a Run Script Build
/// Phase that auto-injects `git rev-parse --short HEAD` at build time. Not
/// done yet to avoid pbxproj edits while the project is fresh.
enum BuildInfo {
    static let label = "Probe v2: auto-reconnect paired Looi on launch · 2026-05-17 · newer than 3c81fd8"
}
