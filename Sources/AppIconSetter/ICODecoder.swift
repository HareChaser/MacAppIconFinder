import AppKit
import Foundation

/// One image inside an .ico container (or inside a Windows executable's icon group).
struct RawIconImage {
    var width: Int      // 0 in the on-disk header means 256
    var height: Int
    var planes: UInt16
    var bitCount: UInt16
    var payload: [UInt8]

    var isPNG: Bool {
        payload.count > 8 && Array(payload[0 ..< 8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    }

    /// Pixel dimensions, resolving the 0-means-256 convention and, for BMP
    /// payloads, preferring the DIB header (which is authoritative for sizes
    /// the byte-sized directory fields cannot express).
    var pixelSize: NSSize {
        if isPNG, let rep = NSBitmapImageRep(data: Data(payload)) {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        if payload.count >= 12 {
            let reader = ByteReader(payload)
            if let w = try? reader.u32(4), let h = try? reader.u32(8), w > 0, h > 0 {
                // The DIB height covers colour + AND mask, hence the halving.
                return NSSize(width: Int(w), height: Int(h) / 2)
            }
        }
        return NSSize(width: width == 0 ? 256 : width, height: height == 0 ? 256 : height)
    }
}

enum ICODecoder {
    enum Error: Swift.Error, LocalizedError {
        case notAnICO
        case noImages

        var errorDescription: String? {
            switch self {
            case .notAnICO: return "That file doesn't look like a Windows icon (.ico)."
            case .noImages: return "No icon images were found in that file."
            }
        }
    }

    /// Parses an .ico / .cur container into its individual images.
    static func parse(_ data: Data) throws -> [RawIconImage] {
        let reader = ByteReader(data)
        guard try reader.u16(0) == 0 else { throw Error.notAnICO }
        let type = try reader.u16(2)
        guard type == 1 || type == 2 else { throw Error.notAnICO }
        let count = Int(try reader.u16(4))
        guard count > 0 else { throw Error.noImages }

        var images: [RawIconImage] = []
        for i in 0 ..< count {
            let entry = 6 + i * 16
            let width = Int(try reader.u8(entry))
            let height = Int(try reader.u8(entry + 1))
            let planes = try reader.u16(entry + 4)
            let bitCount = try reader.u16(entry + 6)
            let size = Int(try reader.u32(entry + 8))
            let offset = Int(try reader.u32(entry + 12))
            guard let payload = try? reader.slice(offset, size) else { continue }
            images.append(RawIconImage(width: width, height: height,
                                       planes: planes, bitCount: bitCount, payload: payload))
        }
        guard !images.isEmpty else { throw Error.noImages }
        return images
    }

    /// Decodes a single icon image. PNG payloads are handed straight to
    /// ImageIO; bare DIB payloads are wrapped in a one-entry .ico container so
    /// ImageIO applies the AND mask for us.
    static func decode(_ raw: RawIconImage) -> NSBitmapImageRep? {
        if raw.isPNG {
            return NSBitmapImageRep(data: Data(raw.payload))
        }

        var container: [UInt8] = []
        container.appendLE(UInt16(0))               // reserved
        container.appendLE(UInt16(1))               // type: icon
        container.appendLE(UInt16(1))               // one image
        container.append(UInt8(raw.width & 0xFF))
        container.append(UInt8(raw.height & 0xFF))
        container.append(0)                          // colour count
        container.append(0)                          // reserved
        container.appendLE(raw.planes)
        container.appendLE(raw.bitCount)
        container.appendLE(UInt32(raw.payload.count))
        container.appendLE(UInt32(22))               // payload offset
        container.append(contentsOf: raw.payload)

        return NSBitmapImageRep(data: Data(container))
    }

    /// Builds a displayable image from a set of raw images, preferring the
    /// largest and deepest one.
    static func bestImage(from raws: [RawIconImage]) -> NSImage? {
        let ranked = raws.sorted { lhs, rhs in
            let l = lhs.pixelSize.width * lhs.pixelSize.height
            let r = rhs.pixelSize.width * rhs.pixelSize.height
            if l != r { return l > r }
            return lhs.bitCount > rhs.bitCount
        }
        for raw in ranked {
            if let rep = decode(raw) {
                let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
                image.addRepresentation(rep)
                return image
            }
        }
        return nil
    }
}
