import Foundation

/// Pulls icon groups out of a Windows PE binary (.exe / .dll) by walking its
/// resource directory: RT_GROUP_ICON (14) names the members, RT_ICON (3) holds
/// the actual images.
enum PEIconExtractor {
    enum Error: Swift.Error, LocalizedError {
        case notAPEFile
        case noResourceSection
        case noIcons

        var errorDescription: String? {
            switch self {
            case .notAPEFile: return "That file isn't a Windows executable."
            case .noResourceSection: return "That executable has no resource section."
            case .noIcons: return "That executable doesn't contain any icons."
            }
        }
    }

    private static let rtIcon: UInt32 = 3
    private static let rtGroupIcon: UInt32 = 14

    private struct Section {
        var virtualAddress: UInt32
        var size: UInt32
        var rawPointer: UInt32
    }

    private struct ResourceEntry {
        var id: UInt32
        var offset: UInt32
        var isDirectory: Bool
    }

    /// One icon group from the executable, in file order.
    struct IconGroup {
        var id: UInt32
        var images: [RawIconImage]
    }

    static func extractIconGroups(from data: Data) throws -> [IconGroup] {
        let reader = ByteReader(data)
        guard reader.matches(0, [0x4D, 0x5A]) else { throw Error.notAPEFile }        // "MZ"
        let peOffset = Int(try reader.u32(0x3C))
        guard reader.matches(peOffset, [0x50, 0x45, 0x00, 0x00]) else { throw Error.notAPEFile } // "PE\0\0"

        let coff = peOffset + 4
        let sectionCount = Int(try reader.u16(coff + 2))
        let optionalHeaderSize = Int(try reader.u16(coff + 16))
        let sectionTable = coff + 20 + optionalHeaderSize

        var sections: [Section] = []
        var resourceSection: Section?
        for i in 0 ..< sectionCount {
            let base = sectionTable + i * 40
            let name = try reader.slice(base, 8)
            let section = Section(virtualAddress: try reader.u32(base + 12),
                                  size: try reader.u32(base + 16),
                                  rawPointer: try reader.u32(base + 20))
            sections.append(section)
            if Array(name.prefix(5)) == Array(".rsrc".utf8) {
                resourceSection = section
            }
        }
        guard let rsrc = resourceSection else { throw Error.noResourceSection }
        let rsrcBase = Int(rsrc.rawPointer)

        // Resource RVAs in leaf data entries are image-relative, so they need
        // the full section table to be translated back to file offsets.
        func fileOffset(forRVA rva: UInt32) -> Int? {
            for section in sections
            where rva >= section.virtualAddress && rva < section.virtualAddress &+ max(section.size, 1) {
                return Int(section.rawPointer + (rva - section.virtualAddress))
            }
            return nil
        }

        func entries(atDirectoryOffset offset: Int) throws -> [ResourceEntry] {
            let named = Int(try reader.u16(rsrcBase + offset + 12))
            let ids = Int(try reader.u16(rsrcBase + offset + 14))
            var result: [ResourceEntry] = []
            for i in 0 ..< (named + ids) {
                let base = rsrcBase + offset + 16 + i * 8
                let name = try reader.u32(base)
                let child = try reader.u32(base + 4)
                result.append(ResourceEntry(id: name & 0x7FFF_FFFF,
                                            offset: child & 0x7FFF_FFFF,
                                            isDirectory: child & 0x8000_0000 != 0))
            }
            return result
        }

        /// Resolves a type-level entry down through the name and language
        /// levels to the bytes of the first available leaf.
        func leafBytes(for entry: ResourceEntry) throws -> [UInt8]? {
            var leafOffset = entry.offset
            var levels = 0
            var current = entry
            while current.isDirectory && levels < 3 {
                guard let next = try entries(atDirectoryOffset: Int(current.offset)).first else { return nil }
                current = next
                leafOffset = next.offset
                levels += 1
            }
            guard !current.isDirectory else { return nil }
            let dataEntry = rsrcBase + Int(leafOffset)
            let rva = try reader.u32(dataEntry)
            let size = Int(try reader.u32(dataEntry + 4))
            guard let offset = fileOffset(forRVA: rva) else { return nil }
            return try? reader.slice(offset, size)
        }

        let roots = try entries(atDirectoryOffset: 0)
        guard let iconType = roots.first(where: { $0.id == rtIcon && $0.isDirectory }),
              let groupType = roots.first(where: { $0.id == rtGroupIcon && $0.isDirectory })
        else { throw Error.noIcons }

        // Map RT_ICON resource id -> raw image bytes.
        var iconsByID: [UInt32: [UInt8]] = [:]
        for entry in try entries(atDirectoryOffset: Int(iconType.offset)) {
            if let bytes = try leafBytes(for: entry) {
                iconsByID[entry.id] = bytes
            }
        }

        var groups: [IconGroup] = []
        for entry in try entries(atDirectoryOffset: Int(groupType.offset)) {
            guard let bytes = try leafBytes(for: entry) else { continue }
            let group = ByteReader(bytes)
            guard let count = try? group.u16(4), count > 0 else { continue }
            var images: [RawIconImage] = []
            for i in 0 ..< Int(count) {
                let base = 6 + i * 14
                guard let width = try? group.u8(base),
                      let height = try? group.u8(base + 1),
                      let planes = try? group.u16(base + 4),
                      let bitCount = try? group.u16(base + 6),
                      let iconID = try? group.u16(base + 12),
                      let payload = iconsByID[UInt32(iconID)]
                else { continue }
                images.append(RawIconImage(width: Int(width), height: Int(height),
                                           planes: planes, bitCount: bitCount, payload: payload))
            }
            if !images.isEmpty {
                groups.append(IconGroup(id: entry.id, images: images))
            }
        }

        guard !groups.isEmpty else { throw Error.noIcons }
        return groups
    }
}
