import Foundation

extension LooiCommand {
    /// FED0 — movement control.
    /// Wire: 2 bytes `[Speed, Turn]`, each a signed Int8 in [-127, +127].
    /// Heartbeat: must be re-sent at `LooiProtocol.Timing.motorHeartbeatInterval`
    /// or the motors disengage.
    /// ✅ Source: andrey-tut, verified.
    enum Movement {
        static let forwardMax: Data    = encode(speed:  127, turn:    0)
        static let backwardMax: Data   = encode(speed: -127, turn:    0)
        static let spinLeftMax: Data   = encode(speed:    0, turn:  127)
        static let spinRightMax: Data  = encode(speed:    0, turn: -127)
        static let stop: Data          = encode(speed:    0, turn:    0)

        /// Build a movement command from signed Int8 speed and turn.
        /// `speed`: positive = forward, negative = backward.
        /// `turn`:  positive = left,    negative = right.
        static func encode(speed: Int8, turn: Int8) -> Data {
            Data([UInt8(bitPattern: speed), UInt8(bitPattern: turn)])
        }

        /// Build from a normalized [-1.0, 1.0] joystick value. Clamps out of range.
        static func normalized(forward: Double, turn: Double) -> Data {
            func scaled(_ v: Double) -> Int8 {
                Int8(Int(v.clamped(to: -1...1) * 127))
            }
            return encode(speed: scaled(forward), turn: scaled(turn))
        }
    }
}
