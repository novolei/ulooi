import Foundation

/// Namespace for typed Looi BLE command builders synthesized from
/// andrey-tut/LOOI-Robot and splattydoesstuff/sooperchargeforbots.
///
/// One sub-namespace per command domain, each in its own file in this directory:
///
/// - `LooiCommand.Movement`    — FED0, 2-byte [speed, turn]
/// - `LooiCommand.Head`        — FED1, 1-byte angle
/// - `LooiCommand.Light`       — FED2, on/off (⚠ partial coverage)
/// - `LooiCommand.Handshake`   — FEDA, init bytes
/// - `LooiCommand.SensorEvent` — FED5/FED9 decoders (TBD post-probe)
/// - `LooiCommand.Rich`        — FE00, 17-byte exploratory
/// - `LooiCommand.Preset`      — UI registry type for CommandView
///
/// `LooiCommand+PresetRegistry.swift` holds the ordered preset list shown
/// in CommandView; it depends on all of the above.
///
/// See `LooiProtocol.swift` for UUIDs, handshake values, timing constants.
public enum LooiCommand {}
