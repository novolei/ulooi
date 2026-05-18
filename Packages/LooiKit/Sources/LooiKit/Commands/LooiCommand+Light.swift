import Foundation

extension LooiCommand {
    /// FED2 — headlight / torch.
    /// Wire: 1 byte. `0x00` = off, non-zero values are visible intensity.
    /// `0xFF` is avoided for app-level "full" because real-device DevTools
    /// testing showed it can be non-visible on FED2.
    public enum Light {
        public nonisolated static let off: Data = Data([0x00])
        public nonisolated static let on: Data  = Data([0x03])
        public nonisolated static let full: Data = Data([0xFE])

        /// Speculative — try other values during probe.
        public nonisolated static func raw(_ value: UInt8) -> Data {
            Data([value])
        }
    }
}
