import Foundation

extension LooiCommand {
    /// FEDA — init handshake.
    /// Re-exposed here for ergonomics; canonical bytes live in
    /// `LooiProtocol.Handshake`.
    /// ✅ Source: andrey-tut, verified.
    enum Handshake {
        static let phase1: Data = LooiProtocol.Handshake.phase1Data
        static let phase2: Data = LooiProtocol.Handshake.phase2Data
    }
}
