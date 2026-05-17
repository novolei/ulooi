import Foundation

extension LooiCommand {
    /// FED1 — head/neck angle.
    /// Wire: 1 byte angle, 0x00…0xFF. Center: 0x5A (≈90°). ~10° per increment.
    /// ✅ Source: andrey-tut, verified.
    enum Head {
        static let center: Data    = Data([0x5A])
        static let fullLeft: Data  = Data([0x00])
        static let fullRight: Data = Data([0xFF])

        /// Raw 1-byte angle command. Clamps to [0, 255].
        static func raw(_ angle: Int) -> Data {
            Data([UInt8(max(0, min(255, angle)))])
        }

        /// Offset from center by signed units (~10° per unit per ref docs).
        /// `delta = 0` → center. `delta = +1` → ~+10° from center.
        static func offsetFromCenter(_ delta: Int) -> Data {
            raw(0x5A + delta)
        }
    }
}
