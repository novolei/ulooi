import Foundation

/// The current motor command that the BLECentral heartbeat sends to FED0
/// every 30ms. Updating this is how the user "drives" the robot — the
/// effect is visible on the next heartbeat tick (≤30ms latency).
///
/// Default is `.stop`. Always reset to `.stop` on disconnect so a
/// subsequent auto-reconnect doesn't immediately resume movement
/// without user intent.
///
/// Carries a human-readable `label` alongside the wire `data` so the
/// ConnectionBanner can show what the robot is "doing right now"
/// without having to reverse-engineer the byte pattern.
public struct MotionState: Sendable, Equatable {
    public nonisolated let label: String
    public nonisolated let data: Data

    public nonisolated init(label: String, data: Data) {
        self.label = label
        self.data = data
    }

    public nonisolated static let stop = MotionState(label: "STOP", data: LooiCommand.Movement.stop)
}

/// Catalog of motion presets shown in CommandView's Motion control section.
/// Each preset, when tapped, replaces `BLECentral.currentMotion` so the
/// heartbeat starts sending it on every tick.
///
/// Values cover the four cardinal directions at max, two diagonals at mid
/// speed (for testing combined speed+turn), and STOP as the safety reset.
/// Add more as the M0.5 probe reveals what Looi tolerates.
public struct MotionPreset: Identifiable, Sendable {
    public nonisolated let id = UUID()
    public nonisolated let label: String
    public nonisolated let bytes: Data

    public nonisolated init(label: String, bytes: Data) {
        self.label = label
        self.bytes = bytes
    }

    public nonisolated static let all: [MotionPreset] = [
        MotionPreset(label: "STOP",                bytes: LooiCommand.Movement.stop),
        MotionPreset(label: "Forward (max)",       bytes: LooiCommand.Movement.forwardMax),
        MotionPreset(label: "Backward (max)",      bytes: LooiCommand.Movement.backwardMax),
        MotionPreset(label: "Spin Left (max)",     bytes: LooiCommand.Movement.spinLeftMax),
        MotionPreset(label: "Spin Right (max)",    bytes: LooiCommand.Movement.spinRightMax),
        MotionPreset(label: "Forward + Left (mid)",  bytes: LooiCommand.Movement.encode(speed: 70, turn: 70)),
        MotionPreset(label: "Forward + Right (mid)", bytes: LooiCommand.Movement.encode(speed: 70, turn: -70)),
        MotionPreset(label: "Backward + Left (mid)", bytes: LooiCommand.Movement.encode(speed: -70, turn: 70)),
        MotionPreset(label: "Backward + Right (mid)",bytes: LooiCommand.Movement.encode(speed: -70, turn: -70)),
    ]
}
