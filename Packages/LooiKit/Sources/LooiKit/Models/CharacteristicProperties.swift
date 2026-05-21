import CoreBluetooth

/// Strongly-typed view of `CBCharacteristic.properties`'s bitmask. Used by
/// probe screens to display + filter on read/write/notify capabilities.
public struct CharacteristicProperties: OptionSet, CustomStringConvertible {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let broadcast    = CharacteristicProperties(rawValue: 0x01)
    public static let read         = CharacteristicProperties(rawValue: 0x02)
    public static let writeNoResp  = CharacteristicProperties(rawValue: 0x04)
    public static let write        = CharacteristicProperties(rawValue: 0x08)
    public static let notify       = CharacteristicProperties(rawValue: 0x10)
    public static let indicate     = CharacteristicProperties(rawValue: 0x20)
    public static let signed       = CharacteristicProperties(rawValue: 0x40)
    public static let extended     = CharacteristicProperties(rawValue: 0x80)

    public var description: String {
        var parts: [String] = []
        if contains(.read)        { parts.append("read") }
        if contains(.write)       { parts.append("write") }
        if contains(.writeNoResp) { parts.append("wnr") }
        if contains(.notify)      { parts.append("notify") }
        if contains(.indicate)    { parts.append("indicate") }
        if contains(.broadcast)   { parts.append("bcast") }
        if contains(.signed)      { parts.append("signed") }
        if contains(.extended)    { parts.append("ext") }
        return parts.joined(separator: "|")
    }
}
