import AppKit
import Foundation
import UniformTypeIdentifiers

/// One selectable icon parsed out of the source file. A .png yields exactly
/// one; a .ico or .exe can yield several.
struct IconCandidate: Identifiable {
    let id = UUID()
    var image: NSImage
    var label: String
}

enum IconLoader {
    enum Error: Swift.Error, LocalizedError {
        case unsupported(String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext):
                return "\(ext.isEmpty ? "That file type" : "." + ext) isn't supported. Use .ico, .png, .jpg, .icns or .exe."
            case .unreadable:
                return "That file couldn't be read as an image."
            }
        }
    }

    static let supportedExtensions = ["ico", "cur", "png", "jpg", "jpeg", "icns", "tiff", "tif", "heic", "bmp", "gif", "exe", "dll"]

    static func load(from url: URL) throws -> [IconCandidate] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "ico", "cur":
            let raws = try ICODecoder.parse(try Data(contentsOf: url))
            return candidates(fromICOImages: raws)

        case "exe", "dll":
            let groups = try PEIconExtractor.extractIconGroups(from: try Data(contentsOf: url))
            return groups.enumerated().compactMap { index, group in
                guard let image = ICODecoder.bestImage(from: group.images) else { return nil }
                let size = Int(image.size.width)
                return IconCandidate(image: image, label: "Icon \(index + 1) · \(size)×\(size)")
            }

        case "png", "jpg", "jpeg", "icns", "tiff", "tif", "heic", "bmp", "gif":
            guard let image = NSImage(contentsOf: url), image.isValid else { throw Error.unreadable }
            let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide })
            let w = rep?.pixelsWide ?? Int(image.size.width)
            let h = rep?.pixelsHigh ?? Int(image.size.height)
            return [IconCandidate(image: image, label: "\(w)×\(h)")]

        default:
            throw Error.unsupported(ext)
        }
    }

    /// The app's own icon, to be restyled in place.
    ///
    /// With no custom icon set, the displayed icon *is* the stock icon, and the
    /// system serves it at up to 2048px — better than most bundled `.icns`
    /// files, which often stop at 256. Once a custom icon exists the displayed
    /// icon can't be trusted as a source (restyling it would stack one
    /// treatment on the last), so fall back to the bundle's own `.icns`.
    /// `isStock` is false only when neither is available — an app that keeps
    /// its icon in an asset catalogue *and* already carries a custom icon.
    static func appIcon(for appURL: URL, hasCustomIcon: Bool) -> (image: NSImage, isStock: Bool) {
        if !hasCustomIcon {
            return (highestResolution(of: NSWorkspace.shared.icon(forFile: appURL.path)), true)
        }
        if let name = Bundle(url: appURL)?.infoDictionary?["CFBundleIconFile"] as? String {
            let file = name.hasSuffix(".icns") ? name : name + ".icns"
            let iconURL = appURL.appendingPathComponent("Contents/Resources/\(file)")
            if let image = NSImage(contentsOf: iconURL), image.isValid {
                return (highestResolution(of: image), true)
            }
        }
        return (highestResolution(of: NSWorkspace.shared.icon(forFile: appURL.path)), false)
    }

    /// System icons carry many representations and report a small `size`;
    /// drawing one straight into a 1024 canvas can pick a low-res rep, so pin
    /// the image to its largest one first.
    static func highestResolution(of image: NSImage) -> NSImage {
        guard let best = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
              best.pixelsWide > 0 else { return image }
        let copy = NSImage(size: NSSize(width: best.pixelsWide, height: best.pixelsHigh))
        copy.addRepresentation(best)
        return copy
    }

    /// Each distinct pixel size in an .ico is offered separately — the biggest
    /// one is usually what you want, but sharper small art sometimes isn't.
    private static func candidates(fromICOImages raws: [RawIconImage]) -> [IconCandidate] {
        let sorted = raws.sorted { lhs, rhs in
            let l = lhs.pixelSize.width * lhs.pixelSize.height
            let r = rhs.pixelSize.width * rhs.pixelSize.height
            if l != r { return l > r }
            return lhs.bitCount > rhs.bitCount
        }
        var seen = Set<String>()
        var result: [IconCandidate] = []
        for raw in sorted {
            guard let rep = ICODecoder.decode(raw) else { continue }
            let key = "\(rep.pixelsWide)x\(rep.pixelsHigh)x\(raw.bitCount)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
            image.addRepresentation(rep)
            result.append(IconCandidate(image: image,
                                        label: "\(rep.pixelsWide)×\(rep.pixelsHigh) · \(raw.bitCount)-bit"))
        }
        return result
    }
}
