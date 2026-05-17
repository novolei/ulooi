import Foundation

extension LooiCommand {
    /// FED1 — head PITCH (up/down tilt). NOT yaw — head left/right turning is
    /// done via FED0 wheel spin (rotate the whole body).
    /// Wire: 1 byte position, 0x00…0xFF. Center: 0x5A.
    /// ✅ Source: andrey-tut + M0.5 hardware probe (corrected from initial
    /// mis-labeling as left/right).
    public enum Head {
        /// Mechanical center / rest position.
        public nonisolated static let center: Data   = Data([0x5A])
        /// Head looks up (tilts back).
        public nonisolated static let lookUp: Data   = Data([0x00])
        /// Head looks down (tilts forward). NOTE: empirically observed to
        /// auto-spring back to center after firing — Looi firmware may
        /// interpret 0xFF as a "nod down" gesture rather than a hold-at-pitch
        /// command. Symmetric behavior at 0x00 not yet verified.
        public nonisolated static let lookDown: Data = Data([0xFF])

        /// Raw 1-byte position command. Clamps to [0, 255].
        public nonisolated static func raw(_ pitch: Int) -> Data {
            Data([UInt8(max(0, min(255, pitch)))])
        }

        /// Offset from center by signed units.
        /// `delta = 0` → center. Negative → tilt up, positive → tilt down.
        public nonisolated static func offsetFromCenter(_ delta: Int) -> Data {
            raw(0x5A + delta)
        }
    }
}
