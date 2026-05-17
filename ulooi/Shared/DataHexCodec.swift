import Foundation

/// Hex encode/decode for `Data`, shared across DevTools probe screens.
extension Data {
    /// Lowercase hex string with space separators, e.g. `"7e a1 03"`.
    var hexEncoded: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// Decode a permissive hex string. Accepts spaces, dashes, colons, newlines
    /// as separators. Returns `nil` if odd nibble count or non-hex content.
    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        self.init(bytes)
    }
}
