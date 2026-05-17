import CoreBluetooth

/// Strongly-typed view of `CBCharacteristic.properties`'s bitmask. Used by
/// probe screens to display + filter on read/write/notify capabilities.
struct CharacteristicProperties: OptionSet, CustomStringConvertible {
    let rawValue: UInt

    static let broadcast    = CharacteristicProperties(rawValue: 0x01)
    static let read         = CharacteristicProperties(rawValue: 0x02)
    static let writeNoResp  = CharacteristicProperties(rawValue: 0x04)
    static let write        = CharacteristicProperties(rawValue: 0x08)
    static let notify       = CharacteristicProperties(rawValue: 0x10)
    static let indicate     = CharacteristicProperties(rawValue: 0x20)
    static let signed       = CharacteristicProperties(rawValue: 0x40)
    static let extended     = CharacteristicProperties(rawValue: 0x80)

    var description: String {
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
