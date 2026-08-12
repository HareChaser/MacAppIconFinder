// Draws AppIconSetter's own icon and writes it as a 1024×1024 PNG.
// Run via Tools/make-icon.sh, which then packs it into Resources/AppIcon.icns.
//
//   swift Tools/MakeAppIcon.swift <output.png>

import AppKit

let side: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()
let context = NSGraphicsContext.current!
context.imageInterpolation = .high

// macOS icons don't fill their canvas — the art sits inside a rounded square
// with room to breathe, which is what makes it sit right next to system icons.
let inset: CGFloat = 100
let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let plateRadius = plate.width * 0.2237
let plateShape = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)

// Plate shadow.
context.saveGraphicsState()
let plateShadow = NSShadow()
plateShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
plateShadow.shadowOffset = NSSize(width: 0, height: -14)
plateShadow.shadowBlurRadius = 34
plateShadow.set()
color(0x4F46E5).setFill()
plateShape.fill()
context.restoreGraphicsState()

// Plate gradient.
context.saveGraphicsState()
plateShape.addClip()
NSGradient(starting: color(0x6D8BFF), ending: color(0x3B2FD6))?
    .draw(in: plate, angle: -90)

// Highlight across the top. A gradient rather than a shape, so it fades out
// instead of leaving a visible seam across the middle of the plate.
let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16),
                                NSColor.white.withAlphaComponent(0)])
gloss?.draw(in: NSRect(x: plate.minX, y: plate.midY,
                       width: plate.width, height: plate.height / 2), angle: -90)
context.restoreGraphicsState()

// Inner rim: a hairline of light along the top edge, dark along the bottom.
context.saveGraphicsState()
plateShape.addClip()
NSColor.white.withAlphaComponent(0.35).setStroke()
let rim = NSBezierPath(roundedRect: plate.insetBy(dx: 2, dy: 2), xRadius: plateRadius, yRadius: plateRadius)
rim.lineWidth = 4
rim.stroke()
context.restoreGraphicsState()

// The magnifier: an app tile seen through a lens.
let lensCenter = NSPoint(x: 452, y: 578)
let lensRadius: CGFloat = 232

context.saveGraphicsState()
let glassShadow = NSShadow()
glassShadow.shadowColor = NSColor(srgbRed: 0.08, green: 0.06, blue: 0.35, alpha: 0.45)
glassShadow.shadowOffset = NSSize(width: 0, height: -16)
glassShadow.shadowBlurRadius = 30
glassShadow.set()

// Handle first, so the lens body overlaps it cleanly.
let direction = NSPoint(x: cos(-.pi / 4), y: sin(-.pi / 4))
let handle = NSBezierPath()
handle.move(to: NSPoint(x: lensCenter.x + direction.x * (lensRadius - 20),
                        y: lensCenter.y + direction.y * (lensRadius - 20)))
handle.line(to: NSPoint(x: lensCenter.x + direction.x * (lensRadius + 150),
                        y: lensCenter.y + direction.y * (lensRadius + 150)))
handle.lineWidth = 78
handle.lineCapStyle = .round
NSColor.white.setStroke()
handle.stroke()

NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
                            width: lensRadius * 2, height: lensRadius * 2)).fill()
context.restoreGraphicsState()

// Lens interior, a shade cooler than pure white so the rim reads as a rim.
let interiorRadius = lensRadius - 42
color(0xEEF1FF).setFill()
NSBezierPath(ovalIn: NSRect(x: lensCenter.x - interiorRadius, y: lensCenter.y - interiorRadius,
                            width: interiorRadius * 2, height: interiorRadius * 2)).fill()

// The app tile under the glass: the thing being swapped.
let tileSide: CGFloat = 212
let tile = NSRect(x: lensCenter.x - tileSide / 2, y: lensCenter.y - tileSide / 2,
                  width: tileSide, height: tileSide)
let tileShape = NSBezierPath(roundedRect: tile, xRadius: tileSide * 0.2237, yRadius: tileSide * 0.2237)
context.saveGraphicsState()
tileShape.addClip()
NSGradient(starting: color(0x5B7BFF), ending: color(0x3B2FD6))?.draw(in: tile, angle: -90)
context.restoreGraphicsState()

// A small arrow inside the tile, echoing the app's own left-to-right flow.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: tile.midX - 44, y: tile.midY))
arrow.line(to: NSPoint(x: tile.midX + 30, y: tile.midY))
arrow.lineWidth = 22
arrow.lineCapStyle = .round
NSColor.white.setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: tile.midX + 8, y: tile.midY + 36))
head.line(to: NSPoint(x: tile.midX + 44, y: tile.midY))
head.line(to: NSPoint(x: tile.midX + 8, y: tile.midY - 36))
head.lineWidth = 22
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Could not encode the icon.\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
