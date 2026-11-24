// Renders Resources/dmg-background.tiff (1x + 2x) for the installer disk image.
// Run once: swift scripts/make-dmg-background.swift
import AppKit

/// Stops the script with a readable message (these are build-time helpers).
func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let size = NSSize(width: 660, height: 400)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    guard let rep else { die("Could not allocate the bitmap") }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Warm canvas with a soft violet glow
    NSColor(srgbRed: 0.965, green: 0.957, blue: 0.941, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSGradient(colors: [NSColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.10), .clear])?
        .draw(fromCenter: NSPoint(x: 330, y: 230), radius: 0, toCenter: NSPoint(x: 330, y: 230), radius: 300, options: [])

    // Arrow from the app (x 170) to Applications (x 490), icons centred at y = 400 - 190
    let y: CGFloat = 210
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 268, y: y))
    arrow.line(to: NSPoint(x: 384, y: y))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    let violet = NSColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.55)
    violet.setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 372, y: y + 13))
    head.line(to: NSPoint(x: 390, y: y))
    head.line(to: NSPoint(x: 372, y: y - 13))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Caption
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.12, green: 0.11, blue: 0.14, alpha: 1),
        .paragraphStyle: para
    ]
    let sub: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12.5),
        .foregroundColor: NSColor(srgbRed: 0.42, green: 0.41, blue: 0.45, alpha: 1),
        .paragraphStyle: para
    ]
    ("Drag SidTree to Applications" as NSString).draw(in: NSRect(x: 0, y: 72, width: size.width, height: 24), withAttributes: title)
    ("Then open it from your Applications folder." as NSString).draw(in: NSRect(x: 0, y: 50, width: size.width, height: 20), withAttributes: sub)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/dmg-background.tiff")
guard let tiff = image.tiffRepresentation(using: .lzw, factor: 1) else { die("Could not encode the TIFF") }
do {
    try tiff.write(to: out)
} catch {
    die("Could not write \(out.path): \(error.localizedDescription)")
}
print("✓ \(out.path)")
