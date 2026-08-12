import Foundation

/// Little-endian random-access reader over a byte buffer.
/// Every accessor is bounds-checked and throws instead of trapping, because the
/// inputs here are untrusted files picked by the user.
struct ByteReader {
    enum Error: Swift.Error, LocalizedError {
        case outOfBounds

        var errorDescription: String? { "The file ended sooner than its headers claim." }
    }

    let bytes: [UInt8]

    init(_ data: Data) { self.bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var count: Int { bytes.count }

    func u8(_ offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < bytes.count else { throw Error.outOfBounds }
        return bytes[offset]
    }

    func u16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 1 < bytes.count else { throw Error.outOfBounds }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    func u32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 3 < bytes.count else { throw Error.outOfBounds }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    func slice(_ offset: Int, _ length: Int) throws -> [UInt8] {
        guard offset >= 0, length >= 0, offset + length <= bytes.count else { throw Error.outOfBounds }
        return Array(bytes[offset ..< (offset + length)])
    }

    func matches(_ offset: Int, _ signature: [UInt8]) -> Bool {
        guard offset >= 0, offset + signature.count <= bytes.count else { return false }
        for (i, byte) in signature.enumerated() where bytes[offset + i] != byte { return false }
        return true
    }
}

extension Array where Element == UInt8 {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
