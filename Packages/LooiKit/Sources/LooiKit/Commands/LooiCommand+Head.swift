import Foundation

extension LooiCommand {
    /// FED1 — head PITCH (up/down tilt). NOT yaw — head left/right turning is
    /// done via FED0 wheel spin (rotate the whole body).
    /// Wire: 1 byte position, 0x00...0xFF. Center: 0x5A.
    /// Source: novolei/LOOI-Robot increments from center for head up and
    /// decrements from center for head down.
    public enum Head {
        /// Mechanical center / rest position.
        public nonisolated static let center: Data   = Data([0x5A])
        /// One step above center: 0x5A + 10.
        public nonisolated static let lookUp: Data   = Data([0x64])
        /// One step below center: 0x5A - 10.
        public nonisolated static let lookDown: Data = Data([0x50])

        /// Raw 1-byte position command. Clamps to [0, 255].
        public nonisolated static func raw(_ pitch: Int) -> Data {
            Data([UInt8(max(0, min(255, pitch)))])
        }

        /// Offset from center by signed units.
        /// `delta = 0` -> center. Positive -> tilt up, negative -> tilt down.
        public nonisolated static func offsetFromCenter(_ delta: Int) -> Data {
            raw(0x5A + delta)
        }
    }
}
