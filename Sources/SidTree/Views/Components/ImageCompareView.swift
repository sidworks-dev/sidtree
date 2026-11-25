import AppKit
import SwiftUI

enum ByteSize {
    static func text(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// "+2.3 KB (+18%)" / "−1 KB (−4%)" / "no change".
    static func delta(old: Int?, new: Int?) -> (String, Int) {
        let before = old ?? 0, after = new ?? 0
        let diff = after - before
        guard diff != 0 else { return ("same size", 0) }
        let sign = diff > 0 ? "+" : "−"
        var text = sign + text(abs(diff))
        if before > 0 {
            let pct = Double(diff) / Double(before) * 100
            text += String(format: abs(pct) < 1 ? " (%@%.1f%%)" : " (%@%.0f%%)", sign, abs(pct))
        }
        return (text, diff)
    }
}

/// "12 KB → 10 KB  −2 KB (−18%)" in the diff header of an image.
struct ByteDelta: View {
    let images: ImageComparison

    var body: some View {
        let (text, diff) = ByteSize.delta(old: images.old?.count, new: images.new?.count)
        Text(text).foregroundStyle(diff > 0 ? Theme.addedText : (diff < 0 ? Theme.removedText : Theme.tertiaryText))
    }
}

/// Before and after side by side on a checkerboard, with pixel size, bytes and the difference.
struct ImageCompareView: View {
    let images: ImageComparison
    var compact = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if compact {
                    HStack(spacing: 6) {
                        Text("Image").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                        ByteDelta(images: images).font(.system(size: 11, design: .monospaced))
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    if let old = images.old {
                        ImageSide(title: images.new == nil ? "Deleted" : "Before", data: old, tint: Theme.removedText)
                    }
                    if let new = images.new {
                        ImageSide(title: images.old == nil ? "Added" : "After", data: new, tint: Theme.addedText)
                    }
                }
            }
            .padding(compact ? 12 : 16)
        }
        .id(images.id)
    }
}

private struct ImageSide: View {
    let title: String
    let data: Data?
    let tint: Color
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.66).foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 4)
                if let data {
                    Text([dimensions, ByteSize.text(data.count)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            ZStack {
                Checkerboard()
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: pixelSize?.width, maxHeight: pixelSize?.height)
                        .padding(12)
                } else {
                    Text(failed ? "Preview not available" : "")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 460)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
        .task(id: data?.count) { @MainActor in
            guard let data else { image = nil; return }
            let decoded = NSImage(data: data)
            image = decoded
            failed = decoded == nil
        }
    }

    private var pixelSize: CGSize? {
        guard let rep = image?.representations.first, rep.pixelsWide > 0 else { return nil }
        // Show pixel art and icons at no more than 2× their size; scale down anything larger.
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        return CGSize(width: CGFloat(rep.pixelsWide) / scale * 2, height: CGFloat(rep.pixelsHigh) / scale * 2)
    }

    private var dimensions: String? {
        guard let rep = image?.representations.first, rep.pixelsWide > 0 else { return nil }
        return "\(rep.pixelsWide)×\(rep.pixelsHigh)"
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            let light = Color(nsColor: Theme.dynamic(0xFFFFFF, 0x3A3835))
            let dark = Color(nsColor: Theme.dynamic(0xF0EDE7, 0x32302D))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            var path = Path()
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    path.addRect(CGRect(x: x, y: y, width: cell, height: cell))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
            context.fill(path, with: .color(dark))
        }
    }
}
