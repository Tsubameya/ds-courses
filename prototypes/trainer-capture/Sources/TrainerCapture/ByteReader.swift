import Foundation

/// Lit une trame Bluetooth champ par champ, en petit-boutiste comme le veulent les normes GATT et ANT+.
/// Chaque lecture renvoie nil si la trame est trop courte, au lieu de planter.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var remaining: Int { bytes.count - offset }

    mutating func uint8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func int8() -> Int8? {
        uint8().map { Int8(bitPattern: $0) }
    }

    mutating func uint16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func int16() -> Int16? {
        uint16().map { Int16(bitPattern: $0) }
    }

    mutating func uint24() -> UInt32? {
        guard remaining >= 3 else { return nil }
        defer { offset += 3 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
    }

    mutating func uint32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        defer { offset += 4 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    @discardableResult
    mutating func skip(_ count: Int) -> Bool {
        guard remaining >= count else { return false }
        offset += count
        return true
    }
}

extension Data {
    /// « 0A 1B 2C » : le format des colonnes brutes du journal de capture.
    var hex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
