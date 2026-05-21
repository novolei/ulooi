import Foundation

extension LooiCommand {
    /// FED1 — head PITCH (up/down tilt). NOT yaw — head left/right turning is
    /// done via FED0 wheel spin (rotate the whole body).
    /// Wire: 1 byte position, 0x00...0xFF. Center: 0x5A.
    /// Real-device M1.2 feedback: DevTools labels need the inverse of the
    /// novolei keyboard labels, and a larger step reaches the useful range.
    public enum Head {
        /// Mechanical center / rest position.
        public nonisolated static let center: Data   = Data([0x5A])
        /// One large step above center label-wise: 0x5A - 0x20.
        public nonisolated static let lookUp: Data   = Data([0x3A])
        /// One large step below center label-wise: 0x5A + 0x20.
        public nonisolated static let lookDown: Data = Data([0x7A])

        /// Raw 1-byte position command. Clamps to [0, 255].
        public nonisolated static func raw(_ pitch: Int) -> Data {
            Data([UInt8(max(0, min(255, pitch)))])
        }

        /// Offset from center by signed units.
        /// `delta = 0` -> center. Positive -> larger pitch byte, negative -> smaller pitch byte.
        public nonisolated static func offsetFromCenter(_ delta: Int) -> Data {
            raw(0x5A + delta)
        }
    }
}
