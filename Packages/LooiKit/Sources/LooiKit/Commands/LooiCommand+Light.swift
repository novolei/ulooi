import Foundation

extension LooiCommand {
    /// FED2 — headlight / torch.
    /// Wire: 1 byte. `0x00` = off, positive signed-byte range is visible
    /// intensity. Real-device DevTools testing showed 0xFE/0xFF are non-visible;
    /// 0x7F is the reliable app-level full value.
    public enum Light {
        public nonisolated static let off: Data = Data([0x00])
        public nonisolated static let on: Data  = Data([0x03])
        public nonisolated static let full: Data = Data([0x7F])

        /// Speculative — try other values during probe.
        public nonisolated static func raw(_ value: UInt8) -> Data {
            Data([value])
        }
    }
}
