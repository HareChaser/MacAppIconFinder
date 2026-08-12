import AppKit

enum IconRenderer {
    static let canvas: CGFloat = 1024

    /// Normalises whatever the user picked into a square 1024×1024 image that
    /// `NSWorkspace.setIcon` can turn into a full icon family, dressed
    /// according to `style`.
    static func render(_ source: NSImage, style: IconStyle) -> NSImage {
        let side = canvas
        let output = NSImage(size: NSSize(width: side, height: side))
        output.lockFocus()
        defer { output.unlockFocus() }
        NSGraphicsContext.current?.imageInterpolation = .high

        guard style != .original else {
            draw(source, in: aspectFit(source.size, into: NSRect(x: 0, y: 0, width: side, height: side)))
            return output
        }

        // Flat sits closer to the canvas edge; the other two leave room for
        // the shadow, the way system icons do.
        let inset = side * (style == .flat ? 0.06 : 0.1)
        let box = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        // 0.2237 is the classic macOS corner; flat rounds a little further,
        // matching the softer tiles of the newer flat look.
        let radius = box.width * (style == .flat ? 0.25 : 0.2237)
        let shape = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        // Clip the art in a separate pass so the shadow below traces the
        // silhouette's alpha rather than a solid backing plate — art with
        // transparency keeps its transparency.
        // Fit the artwork's opaque content, not its canvas. Icons taken from an
        // app or an .icns already carry the standard macOS margin; fitting that
        // margin inside our own would land the body at 0.8 × 0.8 of the canvas
        // and the result would sit visibly smaller than its neighbours.
        let content = opaqueBounds(of: source) ?? NSRect(origin: .zero, size: source.size)

        let plate = NSImage(size: NSSize(width: side, height: side))
        plate.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        shape.addClip()
        draw(source, in: aspectFit(content.size, into: box), from: content)
        plate.unlockFocus()

        if style != .flat {
            let context = NSGraphicsContext.current
            context?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(style == .glass ? 0.34 : 0.26)
            shadow.shadowOffset = NSSize(width: 0, height: style == .glass ? -14 : -10)
            shadow.shadowBlurRadius = style == .glass ? 34 : 26
            shadow.set()
            plate.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            context?.restoreGraphicsState()
        } else {
            plate.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        }

        if style == .glass {
            addGlass(to: shape, box: box, maskedBy: plate)
        }

        return output
    }

    /// The Tahoe-ish treatment: light pooling in the top of the shape, a bright
    /// specular smear near the top edge, and a rim that catches light above and
    /// darkens below so the edge reads as thickness.
    ///
    /// The whole treatment is built in its own layer and then masked by the
    /// artwork's alpha. Clipping to the rounded square alone is not enough:
    /// art that doesn't reach the edges (most app icons carry their own
    /// margin) would otherwise gain a ghostly translucent square around it.
    private static func addGlass(to shape: NSBezierPath, box: NSRect, maskedBy plate: NSImage) {
        let overlay = NSImage(size: NSSize(width: canvas, height: canvas))
        overlay.lockFocus()
        guard let context = NSGraphicsContext.current else {
            overlay.unlockFocus()
            return
        }
        context.saveGraphicsState()
        shape.addClip()

        NSGradient(colors: [NSColor.white.withAlphaComponent(0.18),
                            NSColor.white.withAlphaComponent(0.0)])?
            .draw(in: NSRect(x: box.minX, y: box.midY,
                             width: box.width, height: box.height / 2), angle: -90)

        // Radial and centred, reaching zero alpha exactly at the ellipse's own
        // boundary — an off-centre or two-stop version leaves a faint ring
        // where the gradient runs out before the edge does.
        let specular = NSBezierPath(ovalIn: NSRect(x: box.minX + box.width * 0.10,
                                                   y: box.maxY - box.height * 0.40,
                                                   width: box.width * 0.80,
                                                   height: box.height * 0.34))
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.32),
                            NSColor.white.withAlphaComponent(0.10),
                            NSColor.white.withAlphaComponent(0.0)],
                   atLocations: [0, 0.45, 1], colorSpace: .sRGB)?
            .draw(in: specular, relativeCenterPosition: .zero)

        NSGradient(colors: [NSColor.black.withAlphaComponent(0.0),
                            NSColor.black.withAlphaComponent(0.12)])?
            .draw(in: NSRect(x: box.minX, y: box.minY,
                             width: box.width, height: box.height * 0.35), angle: -90)

        let rim = NSBezierPath(roundedRect: box.insetBy(dx: 5, dy: 5),
                               xRadius: box.width * 0.2237, yRadius: box.width * 0.2237)
        rim.lineWidth = 10
        NSColor.white.withAlphaComponent(0.16).setStroke()
        rim.stroke()

        // The rim catches more light along the top. Masking a full stroke with
        // a vertical alpha ramp keeps that falloff continuous — clipping to the
        // top half instead leaves a visible step at the left and right edges.
        let lit = NSImage(size: NSSize(width: canvas, height: canvas))
        lit.lockFocus()
        NSColor.white.setStroke()
        rim.stroke()
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        NSGradient(colors: [NSColor.white.withAlphaComponent(1.0),
                            NSColor.white.withAlphaComponent(0.0)])?
            .draw(in: box, angle: -90)
        lit.unlockFocus()
        lit.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 0.45)

        context.restoreGraphicsState()
        plate.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        overlay.unlockFocus()

        overlay.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// The artwork's opaque extent, in the image's own coordinates.
    ///
    /// The threshold ignores the faint spread of a baked-in drop shadow, which
    /// would otherwise count as content and re-introduce the margin we're
    /// trying to remove. Returns nil when the image is empty or already tight.
    private static func opaqueBounds(of image: NSImage) -> NSRect? {
        let sample: CGFloat = 512
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(sample / image.size.width, sample / image.size.height, 1)
        let width = Int((image.size.width * scale).rounded())
        let height = Int((image.size.height * scale).rounded())
        guard width > 1, height > 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0 ..< height {
            for x in 0 ..< width where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.35 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // Back to the image's coordinate space, which counts y from the bottom.
        let sx = image.size.width / CGFloat(width)
        let sy = image.size.height / CGFloat(height)
        return NSRect(x: CGFloat(minX) * sx,
                      y: CGFloat(height - 1 - maxY) * sy,
                      width: CGFloat(maxX - minX + 1) * sx,
                      height: CGFloat(maxY - minY + 1) * sy)
    }

    private static func draw(_ image: NSImage, in rect: NSRect, from source: NSRect = .zero) {
        image.draw(in: rect,
                   from: source,
                   operation: .sourceOver,
                   fraction: 1.0,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    private static func aspectFit(_ size: NSSize, into box: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return NSRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }

    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
