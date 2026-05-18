import Foundation

extension LooiCommand {
    /// Ordered preset list shown as quick-fire buttons in CommandView.
    ///
    /// Order matters: init handshake first (must be hit before anything else
    /// responds), then primitives by domain (movement → head → light), then
    /// experimental (Rich/FE00).
    public nonisolated static let allPresets: [Preset] = [
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

        // Note: Movement presets were removed from this registry — they need
        // to update BLECentral.currentMotion (so heartbeat continues to send
        // them) rather than firing a single-shot write that gets immediately
        // overwritten by the next heartbeat tick. Motion is now controlled
        // via CommandView's "Motion control" section (uses MotionPreset.all).

        // 2. Head (FED1 = pitch, not yaw — corrected from initial mis-labeling)
        Preset(label: "Head — center (0x5A)",
               source: "andrey-tut", status: .verified,
               characteristic: LooiProtocol.Char.head, bytes: Head.center, note: nil),
        Preset(label: "Head — look up step (0x64 from center)",
               source: "andrey-tut+M0.5", status: .verified,
               characteristic: LooiProtocol.Char.head, bytes: Head.lookUp,
               note: "novolei increments head_pos from 0x5A for head up. Yaw/turning is via FED0 wheel spin."),
        Preset(label: "Head — look down step (0x50 from center)",
               source: "andrey-tut+M0.5", status: .verified,
               characteristic: LooiProtocol.Char.head, bytes: Head.lookDown,
               note: "novolei decrements head_pos from 0x5A for head down."),

        // 3. Light
        Preset(label: "Light — full (0x7F)",
               source: "M0.5+DevTools", status: .verified,
               characteristic: LooiProtocol.Char.light, bytes: Light.full,
               note: "App-level full uses signed positive max; 0xFE/0xFF were non-visible in real-device DevTools testing."),
        Preset(label: "Light — on/min visible (0x03)",
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
