import Foundation

extension LooiCommand {
    /// Ordered preset list shown as quick-fire buttons in CommandView.
    ///
    /// Order matters: init handshake first (must be hit before anything else
    /// responds), then primitives by domain (movement → head → light), then
    /// experimental (Rich/FE00).
    static let allPresets: [Preset] = [
        // 0. Init handshake — must be hit in order before any other write responds
        Preset(
            label: "INIT 1/2 — handshake 0x01",
            source: "andrey-tut",
            status: .verified,
            characteristic: LooiProtocol.Char.handshake,
            bytes: Handshake.phase1,
            note: "Step 1 of init. After this, manually subscribe to sensors (FED5) and telemetry (FED9) from the Sense tab, then hit INIT 2/2."
        ),
        Preset(
            label: "INIT 2/2 — handshake 0x03",
            source: "andrey-tut",
            status: .verified,
            characteristic: LooiProtocol.Char.handshake,
            bytes: Handshake.phase2,
            note: "Step 2. After this, motion / light commands should respond."
        ),

        // 1. Movement
        Preset(label: "STOP (movement = 0,0)",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.movement, bytes: Movement.stop,
               note: "Always safe; resets motors. Send on app background / disconnect."),
        Preset(label: "Forward max",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.movement, bytes: Movement.forwardMax,
               note: "Heartbeat required: re-send within 30ms or motors disengage."),
        Preset(label: "Backward max",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.movement, bytes: Movement.backwardMax,
               note: nil),
        Preset(label: "Spin left max",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.movement, bytes: Movement.spinLeftMax,
               note: nil),
        Preset(label: "Spin right max",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.movement, bytes: Movement.spinRightMax,
               note: nil),

        // 2. Head
        Preset(label: "Head — center (0x5A)",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.head, bytes: Head.center, note: nil),
        Preset(label: "Head — full left (0x00)",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.head, bytes: Head.fullLeft, note: nil),
        Preset(label: "Head — full right (0xFF)",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.head, bytes: Head.fullRight, note: nil),

        // 3. Light
        Preset(label: "Light — on (0x03)",
               source: "sooperchargeforbots", status: .unverified,
               characteristic: LooiProtocol.Char.light, bytes: Light.on,
               note: "Try other values 0x01, 0x02, 0x04+ to map brightness or RGB. Record results."),
        Preset(label: "Light — off (0x00)",
               source: "sooperchargeforbots", status: .unverified,
               characteristic: LooiProtocol.Char.light, bytes: Light.off, note: nil),

        // 4. Rich command (experimental, FE00)
        Preset(label: "RICH — reference example",
               source: "sooperchargeforbots", status: .experimental,
               characteristic: LooiProtocol.Char.richCommand, bytes: Rich.referenceExample,
               note: "17-byte packet from sooper README. Observe whatever the robot does."),
    ]
}
