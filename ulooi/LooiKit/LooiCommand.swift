import CoreBluetooth
import Foundation

/// Initial Looi BLE command dictionary, sourced from public reference repos.
///
/// **STATUS — M0.5: ALL UNVERIFIED.**
/// Every byte sequence and UUID here is copied from the references below
/// and MUST be validated against the actual Looi firmware in this milestone.
/// Validated entries get marked `verified: true` and recorded in
/// `docs/m0-5-prototype-findings.md`.
///
/// References:
/// - andrey-tut/LOOI-Robot   (BLE protocol reverse engineering, Python)
/// - splattydoesstuff/sooperchargeforbots   (Looi mod tooling, Android)
enum LooiCommand {
    // MARK: - Service / characteristic UUIDs (UNVERIFIED — fill in after Scan)
    //
    // TODO M0.5: replace with actual values discovered via ScanView → InspectView.
    // The references mention Nordic UART-style services; that's a starting hypothesis.

    static let candidateServiceUUIDs: [CBUUID] = [
        // CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),  // Nordic UART (hypothesis)
    ]

    // MARK: - Motion presets (UNVERIFIED)

    enum Motion {
        // Each entry: (label, source, bytes). All `verified: false` until probed.
        static let wave_from_andreyTut: (label: String, source: String, bytes: Data) = (
            label: "wave (andrey-tut)",
            source: "andrey-tut/LOOI-Robot",
            bytes: Data([0x00])  // TODO: replace with actual bytes from ref
        )

        static let wave_from_sooper: (label: String, source: String, bytes: Data) = (
            label: "wave (sooperchargeforbots)",
            source: "splattydoesstuff/sooperchargeforbots",
            bytes: Data([0x00])  // TODO: replace with actual bytes from ref
        )

        static let turnHeadLeft: (label: String, source: String, bytes: Data) = (
            label: "head left",
            source: "andrey-tut/LOOI-Robot",
            bytes: Data([0x00])  // TODO
        )

        static let turnHeadRight: (label: String, source: String, bytes: Data) = (
            label: "head right",
            source: "andrey-tut/LOOI-Robot",
            bytes: Data([0x00])  // TODO
        )
    }

    // MARK: - Light presets (UNVERIFIED)

    enum Light {
        static let red: (label: String, source: String, bytes: Data) = (
            label: "set color red",
            source: "andrey-tut/LOOI-Robot",
            bytes: Data([0x00])  // TODO
        )

        static let green: (label: String, source: String, bytes: Data) = (
            label: "set color green",
            source: "andrey-tut/LOOI-Robot",
            bytes: Data([0x00])  // TODO
        )

        static let blue: (label: String, source: String, bytes: Data) = (
            label: "set color blue",
            source: "andrey-tut/LOOI-Robot",
            bytes: Data([0x00])  // TODO
        )

        static let off: (label: String, source: String, bytes: Data) = (
            label: "lights off",
            source: "andrey-tut/LOOI-Robot",
            bytes: Data([0x00])  // TODO
        )
    }

    // MARK: - Convenience

    /// All registered presets for the CommandView grid (extend as you discover more).
    static let allPresets: [(label: String, source: String, bytes: Data)] = [
        Motion.wave_from_andreyTut,
        Motion.wave_from_sooper,
        Motion.turnHeadLeft,
        Motion.turnHeadRight,
        Light.red,
        Light.green,
        Light.blue,
        Light.off,
    ]
}
