import Foundation

extension LooiCommand {
    /// FE00 — 17-byte rich command channel. Layer 2; defer to M3+.
    /// Coordinates motor + LED + screen animations atomically.
    /// ⚠️ Source: sooperchargeforbots README. Opcode table incomplete —
    /// completing it would require sniffing the official app's BLE traffic.
    /// M0.5/M1/M2/M3 base experience does not need this (Layer 1 covers it).
    public enum Rich {
        /// Build a raw 17-byte rich command. Use ONLY when probing FE00.
        public nonisolated static func raw(
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

        /// Reference example from sooperchargeforbots README, byte-for-byte:
        /// `00 07 00 FF 05 00 00 00 00 64 02 0A 96 02 14 00 02`
        public nonisolated static let referenceExample: Data = Data([
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
}
