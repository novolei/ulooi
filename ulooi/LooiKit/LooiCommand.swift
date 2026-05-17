import CoreBluetooth
import Foundation

/// Typed command builders for the Looi BLE protocol.
///
/// Synthesized from andrey-tut/LOOI-Robot (✅ Python-verified) and
/// splattydoesstuff/sooperchargeforbots (⚠️ Android mods, less verified).
/// See `LooiProtocol.swift` for UUIDs, handshake, and timing.
///
/// Every command's source is annotated. The M0.5 probe must verify each one
/// against the actual hardware/firmware in use; record results in
/// `docs/m0-5-prototype-findings.md`.
enum LooiCommand {

    // MARK: - Movement (Char.movement / FED0)
    //
    // Wire format: 2 bytes `[Speed, Turn]`, each a signed Int8 in [-127, +127].
    // Heartbeat: must be re-sent at LooiProtocol.Timing.motorHeartbeatInterval
    // or the motors disengage.
    // ✅ Source: andrey-tut.

    enum Movement {
        /// Maximum forward speed.
        public static let forwardMax: Data = encode(speed: 127, turn: 0)
        /// Maximum backward speed.
        public static let backwardMax: Data = encode(speed: -127, turn: 0)
        /// Spin in place, counter-clockwise (left).
        public static let spinLeftMax: Data = encode(speed: 0, turn: 127)
        /// Spin in place, clockwise (right).
        public static let spinRightMax: Data = encode(speed: 0, turn: -127)
        /// Halt motors. Send this when releasing controls.
        public static let stop: Data = encode(speed: 0, turn: 0)

        /// Build a movement command from signed Int8 speed and turn.
        /// `speed`: positive = forward, negative = backward.
        /// `turn`:  positive = left,    negative = right.
        public static func encode(speed: Int8, turn: Int8) -> Data {
            Data([UInt8(bitPattern: speed), UInt8(bitPattern: turn)])
        }

        /// Build from a normalized [-1.0, 1.0] joystick value. Clamps out of range.
        public static func normalized(forward: Double, turn: Double) -> Data {
            func clamp(_ v: Double) -> Int8 {
                let scaled = Int(v.clamped(to: -1...1) * 127)
                return Int8(scaled)
            }
            return encode(speed: clamp(forward), turn: clamp(turn))
        }
    }

    // MARK: - Head (Char.head / FED1)
    //
    // Wire format: 1 byte angle, 0x00...0xFF.
    // Center: 0x5A (≈90°). Each increment is ~10° per andrey-tut docs.
    // ✅ Source: andrey-tut.

    enum Head {
        /// Mechanical center (≈90°).
        public static let center: Data = Data([0x5A])
        /// All-the-way left.
        public static let fullLeft: Data = Data([0x00])
        /// All-the-way right.
        public static let fullRight: Data = Data([0xFF])

        /// Raw 1-byte angle command. Clamps to [0, 255].
        public static func raw(_ angle: Int) -> Data {
            let clamped = max(0, min(255, angle))
            return Data([UInt8(clamped)])
        }

        /// Offset from center by signed degrees (∼10° per unit per docs; treat as advisory).
        /// `delta = 0` → center. `delta = +10` → ~+100° (right of center per byte order).
        public static func offsetFromCenter(_ delta: Int) -> Data {
            let centerValue = 0x5A
            return raw(centerValue + delta)
        }
    }

    // MARK: - Light / Torch (Char.light / FED2)
    //
    // Wire format: 1 byte. 0x00 = off, 0x03 = on.
    // ⚠️ Source: sooperchargeforbots only (not in andrey-tut). Verify in M0.5.
    // Specifically unknown:
    //   - is there a brightness level beyond on/off?
    //   - is it a torch (white LED only) or RGB?
    //   - if values between 0x00 and 0x03 mean something, we don't know.

    enum Light {
        public static let off: Data = Data([0x00])
        public static let on: Data = Data([0x03])

        /// Speculative — try other values during probe to map full range.
        public static func raw(_ value: UInt8) -> Data {
            Data([value])
        }
    }

    // MARK: - Handshake (Char.handshake / FEDA)
    //
    // Re-exposed here for ergonomics; canonical bytes live in LooiProtocol.Handshake.
    // ✅ Source: andrey-tut, verified.

    enum Handshake {
        public static let phase1: Data = LooiProtocol.Handshake.phase1Data
        public static let phase2: Data = LooiProtocol.Handshake.phase2Data
    }

    // MARK: - Sensor decoding (Char.sensors / FED5 + Char.telemetry / FED9)
    //
    // ❓ Wire format incomplete. Both repos confirm the channels carry touch / cliff
    // sensors / TOF distance / battery stream, but neither documents the byte layout.
    // The M0.5 SenseView lets you subscribe and observe raw bytes — record what
    // physical actions produce what byte patterns in the findings doc, then come back
    // and implement decoders here.

    enum SensorEvent {
        // Will be filled in as M0.5 probe reveals byte → semantic mappings.
        // Example skeleton:
        //
        // public struct Touch {
        //     public let zone: Zone     // head / chin / back / ...
        //     public let intensity: UInt8
        // }
        // public static func decode(_ data: Data) -> SensorEvent? { ... }
    }

    // MARK: - Rich command (Char.richCommand / FE00) — Layer 2
    //
    // ⚠️ Defer to M3 or later. 17-byte packet with sequence counter, opcode, masks,
    // payload, magnitude, params, duration, checksum/footer.
    // sooperchargeforbots documents the layout but not the opcode table — to use this
    // we'd have to capture official-app traffic and reverse opcodes. Not needed for
    // M0.5/M1/M2/M3 base experience (Layer 1 covers it).

    enum Rich {
        /// Build a raw 17-byte rich command. Use ONLY when probing FE00 against captures.
        public static func raw(
            seq: UInt8,
            opcode: UInt8,
            subOp: UInt8 = 0,
            maskA: UInt8 = 0,
            maskB: UInt8 = 0,
            payload: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0),
            value: UInt8 = 0,
            params: (p1: UInt8, p2: UInt8, p3: UInt8, p4: UInt8) = (0, 0, 0, 0),
            duration: UInt8 = 0,
            footer: UInt8 = 0
        ) -> Data {
            Data([
                seq, opcode, subOp, maskA, maskB,
                payload.0, payload.1, payload.2, payload.3,
                value,
                params.p1, params.p2,
                duration,
                params.p3, params.p4,
                0x00,
                footer,
            ])
        }

        /// The reference example from sooperchargeforbots README, byte-for-byte:
        /// `00 07 00 FF 05 00 00 00 00 64 02 0A 96 02 14 00 02`
        public static let referenceExample: Data = Data([
            0x00, 0x07, 0x00, 0xFF, 0x05,
            0x00, 0x00, 0x00, 0x00,
            0x64,
            0x02, 0x0A,
            0x96,
            0x02, 0x14,
            0x00,
            0x02,
        ])
    }

    // MARK: - Preset registry for the CommandView UI

    /// A preset entry shown in CommandView. Includes the target characteristic so the
    /// UI can dispatch to the right write target without user manually picking it.
    struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let source: String
        let status: Status
        let characteristic: CBUUID
        let bytes: Data
        let note: String?

        enum Status: String {
            case verified = "✅"
            case unverified = "⚠️"
            case experimental = "❓"
        }
    }

    /// Ordered list of presets the CommandView shows as quick-fire buttons.
    /// Order matters: init handshake first, then primitives by domain, then experimental.
    static let allPresets: [Preset] = [
        // 0. Init handshake — must be hit in order, before anything else
        .init(
            label: "INIT 1/2 — handshake 0x01",
            source: "andrey-tut",
            status: .verified,
            characteristic: LooiProtocol.Char.handshake,
            bytes: Handshake.phase1,
            note: "Step 1 of init. After this, manually subscribe to sensors (FED5) and telemetry (FED9) from the Sense tab, then hit INIT 2/2."
        ),
        .init(
            label: "INIT 2/2 — handshake 0x03",
            source: "andrey-tut",
            status: .verified,
            characteristic: LooiProtocol.Char.handshake,
            bytes: Handshake.phase2,
            note: "Step 2. After this, motion / light commands should respond."
        ),

        // 1. Movement
        .init(label: "STOP (movement = 0,0)",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.movement, bytes: Movement.stop,
              note: "Always available; resets motors. Send this on app background / disconnect."),
        .init(label: "Forward max",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.movement, bytes: Movement.forwardMax,
              note: "Heartbeat required: re-send within 30ms or motors disengage."),
        .init(label: "Backward max",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.movement, bytes: Movement.backwardMax,
              note: nil),
        .init(label: "Spin left max",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.movement, bytes: Movement.spinLeftMax,
              note: nil),
        .init(label: "Spin right max",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.movement, bytes: Movement.spinRightMax,
              note: nil),

        // 2. Head
        .init(label: "Head — center (0x5A)",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.head, bytes: Head.center, note: nil),
        .init(label: "Head — full left (0x00)",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.head, bytes: Head.fullLeft, note: nil),
        .init(label: "Head — full right (0xFF)",
              source: "andrey-tut", status: .verified,
              characteristic: LooiProtocol.Char.head, bytes: Head.fullRight, note: nil),

        // 3. Light
        .init(label: "Light — on (0x03)",
              source: "sooperchargeforbots", status: .unverified,
              characteristic: LooiProtocol.Char.light, bytes: Light.on,
              note: "Try other values 0x01, 0x02, 0x04+ to map brightness or RGB. Record results."),
        .init(label: "Light — off (0x00)",
              source: "sooperchargeforbots", status: .unverified,
              characteristic: LooiProtocol.Char.light, bytes: Light.off, note: nil),

        // 4. Rich command (experimental, FE00)
        .init(label: "RICH — reference example",
              source: "sooperchargeforbots", status: .experimental,
              characteristic: LooiProtocol.Char.richCommand, bytes: Rich.referenceExample,
              note: "17-byte packet from sooper README. Observe whatever the robot does."),
    ]
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
