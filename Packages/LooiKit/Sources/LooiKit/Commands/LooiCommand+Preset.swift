import CoreBluetooth
import Foundation

extension LooiCommand {
    /// A preset entry surfaced in CommandView. Carries its own target
    /// characteristic so the UI can auto-dispatch (no manual char picker).
    struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let source: String
        let status: Status
        let characteristic: CBUUID
        let bytes: Data
        let note: String?

        enum Status: String {
            case verified = "✅"
            case unverified = "⚠️"
            case experimental = "❓"
        }
    }
}
