// Renders Resources/AppIcon.icns from the Sidworks logo mark.
import AppKit

/// Stops the script with a readable message (these are build-time helpers).
func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3, let logo = NSImage(contentsOfFile: args[1]) else { die("usage: make-icon <logo.png> <output-dir>") }
let outDir = args[2]

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)
    guard let rep else { die("Could not allocate the bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.098
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                        NSColor(srgbRed: 0.955, green: 0.94, blue: 0.985, alpha: 1)])?.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.12).setStroke()
    path.lineWidth = max(1, s * 0.004)
    path.stroke()

    let h = rect.height * 0.62
    let w = h * logo.size.width / logo.size.height
    logo.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { die("Could not encode PNG") }
    return png
}

let iconset = outDir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    do {
        try render(base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
        try render(base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
    } catch {
        die("Could not write the iconset: \(error.localizedDescription)")
    }
}
