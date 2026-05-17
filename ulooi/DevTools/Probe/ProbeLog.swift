import Foundation
import Observation

@MainActor
@Observable
final class ProbeLog {
    static let shared = ProbeLog()

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
    }

    enum Level: String, CaseIterable {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERR"
        case bytes = "RAW"
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 2000

    func info(_ message: String) { append(.info, message) }
    func warn(_ message: String) { append(.warn, message) }
    func error(_ message: String) { append(.error, message) }
    func bytes(_ label: String, _ data: Data) {
        append(.bytes, "\(label): \(data.hexEncoded)")
    }

    func clear() { entries.removeAll() }

    func export() -> String {
        entries.map { e in
            let ts = ISO8601DateFormatter().string(from: e.timestamp)
            return "\(ts) [\(e.level.rawValue)] \(e.message)"
        }.joined(separator: "\n")
    }

    private func append(_ level: Level, _ message: String) {
        entries.append(Entry(timestamp: Date(), level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

extension Data {
    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
