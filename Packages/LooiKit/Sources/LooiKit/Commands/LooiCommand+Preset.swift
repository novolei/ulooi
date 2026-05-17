import CoreBluetooth
import Foundation

extension LooiCommand {
    /// A preset entry surfaced in CommandView. Carries its own target
    /// characteristic so the UI can auto-dispatch (no manual char picker).
    public struct Preset: Identifiable {
        public let id = UUID()
        public let label: String
        public let source: String
        public let status: Status
        // nonisolated(unsafe): CBUUID is a reference type not declared Sendable;
        // these values are compile-time constants so sharing across isolation
        // contexts is safe in practice.
        public nonisolated(unsafe) let characteristic: CBUUID
        public let bytes: Data
        public let note: String?

        public nonisolated init(label: String, source: String, status: Status, characteristic: CBUUID, bytes: Data, note: String?) {
            self.label = label
            self.source = source
            self.status = status
            self.characteristic = characteristic
            self.bytes = bytes
            self.note = note
        }

        public enum Status: String {
            case verified = "✅"
            case unverified = "⚠️"
            case experimental = "❓"
        }
    }
}
