import Foundation

/// A peripheral the transport has discovered during scan. Sendable so it can
/// cross actor boundaries (the discovered stream may be consumed on any
/// isolation domain). Carries enough context to decide whether to connect.
///
/// `advertisedServices` stores UUID strings rather than CBUUID so the struct
/// remains `Sendable` under Swift 6 strict concurrency (CBUUID is not Sendable).
///
/// Stored properties are marked `nonisolated(unsafe)` so they remain readable
/// from nonisolated contexts without requiring a MainActor hop — the target has
/// `defaultIsolation = MainActor`, which would otherwise make every stored `let`
/// MainActor-isolated. All fields are immutable value types, so this is safe.
public struct DiscoveredPeripheral: Sendable, Identifiable {
    public nonisolated(unsafe) let id: UUID
    public nonisolated(unsafe) let name: String
    public nonisolated(unsafe) let rssi: Int
    /// UUIDs as strings (CBUUID.uuidString) — CBUUID is not Sendable in Swift 6.
    public nonisolated(unsafe) let advertisedServices: [String]
    public nonisolated(unsafe) let manufacturerData: Data?
    public nonisolated(unsafe) let lastSeen: Date

    public nonisolated init(
        id: UUID,
        name: String,
        rssi: Int,
        advertisedServices: [String],
        manufacturerData: Data?,
        lastSeen: Date
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.advertisedServices = advertisedServices
        self.manufacturerData = manufacturerData
        self.lastSeen = lastSeen
    }
}

extension DiscoveredPeripheral: Equatable {
    public nonisolated static func == (lhs: DiscoveredPeripheral, rhs: DiscoveredPeripheral) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.rssi == rhs.rssi
            && lhs.advertisedServices == rhs.advertisedServices
            && lhs.manufacturerData == rhs.manufacturerData
            && lhs.lastSeen == rhs.lastSeen
    }
}

extension DiscoveredPeripheral: Hashable {
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(rssi)
        hasher.combine(advertisedServices)
        hasher.combine(manufacturerData)
        hasher.combine(lastSeen)
    }

    /// Explicit nonisolated `hashValue` — prevents the synthesized computed
    /// property from inheriting `@MainActor` isolation from the target default.
    public nonisolated var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}
