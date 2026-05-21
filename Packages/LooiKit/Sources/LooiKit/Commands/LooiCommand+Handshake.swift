import Foundation

extension LooiCommand {
    /// FEDA — init handshake.
    /// Re-exposed here for ergonomics; canonical bytes live in
    /// `LooiProtocol.Handshake`.
    /// ✅ Source: andrey-tut, verified.
    public enum Handshake {
        public nonisolated static let phase1: Data = LooiProtocol.Handshake.phase1Data
        public nonisolated static let phase2: Data = LooiProtocol.Handshake.phase2Data
    }
}
