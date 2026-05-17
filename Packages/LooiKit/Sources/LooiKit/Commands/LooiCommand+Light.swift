import Foundation

extension LooiCommand {
    /// FED2 — headlight / torch.
    /// Wire: 1 byte. `0x00` = off, `0x03` = on. Values between unknown.
    /// ⚠️ Source: sooperchargeforbots only (not in andrey-tut).
    /// M0.5 probe must verify and try the full 0x01..0xFF range to discover
    /// whether there's a brightness gradient or RGB encoding.
    enum Light {
        static let off: Data = Data([0x00])
        static let on: Data  = Data([0x03])

        /// Speculative — try other values during probe.
        static func raw(_ value: UInt8) -> Data {
            Data([value])
        }
    }
}
