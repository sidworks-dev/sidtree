import AppKit
import SwiftUI

/// Warm, calm palette: off-white canvas, white cards, violet accent.
enum Theme {
    static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: alpha)
        }
    }

    // AppKit
    static let nsAccent = dynamic(0x7C3AED, 0x9B6CFF)
    static let nsCanvas = dynamic(0xF6F4F0, 0x17161A)
    static let nsSidebar = dynamic(0xFBFAF7, 0x1D1C21)
    static let nsCard = dynamic(0xFFFFFF, 0x232228)
    static let nsBorder = dynamic(0xE8E4DC, 0x33313A)
    static let nsSubtle = dynamic(0xF4F2EE, 0x2A2930)
    static let nsSelection = dynamic(0xEFE8FD, 0x2F2745)
    static let nsText = dynamic(0x1F1D24, 0xECEAF2)
    static let nsSecondaryText = dynamic(0x6B6874, 0x9C99A6)
    static let nsAddedBg = dynamic(0xE7F6EC, 0x1C3326)
    static let nsRemovedBg = dynamic(0xFCEBEB, 0x3A2023)
    static let nsAddedText = dynamic(0x1A7F43, 0x6FD39A)
    static let nsRemovedText = dynamic(0xB42318, 0xF28B82)

    // SwiftUI
    static let accent = Color(nsColor: nsAccent)
    static let canvas = Color(nsColor: nsCanvas)
    static let sidebar = Color(nsColor: nsSidebar)
    static let card = Color(nsColor: nsCard)
    static let border = Color(nsColor: nsBorder)
    static let subtle = Color(nsColor: nsSubtle)
    static let selection = Color(nsColor: nsSelection)
    static let text = Color(nsColor: nsText)
    static let secondaryText = Color(nsColor: nsSecondaryText)
    static let addedBg = Color(nsColor: nsAddedBg)
    static let removedBg = Color(nsColor: nsRemovedBg)
    static let addedText = Color(nsColor: nsAddedText)
    static let removedText = Color(nsColor: nsRemovedText)

    static let green = Color(nsColor: dynamic(0x16A34A, 0x4ADE80))
    static let greenSoft = Color(nsColor: dynamic(0xE7F6EC, 0x1C3326))
    static let orange = Color(nsColor: dynamic(0xD97706, 0xFBBF24))
    static let orangeSoft = Color(nsColor: dynamic(0xFEF3C7, 0x3A2F12))
    static let red = Color(nsColor: dynamic(0xDC2626, 0xF87171))
    static let redSoft = Color(nsColor: dynamic(0xFDECEC, 0x3A2023))
    static let blue = Color(nsColor: dynamic(0x2563EB, 0x60A5FA))
    static let blueSoft = Color(nsColor: dynamic(0xE8EFFD, 0x1D2840))
    static let violetSoft = Color(nsColor: dynamic(0xF1EAFE, 0x2D2544))
    static let graySoft = Color(nsColor: dynamic(0xEFEDE8, 0x2C2B31))

    static let radius: CGFloat = 12
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Reusable building blocks

struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// White bordered button, BerryPath style. `prominent` gives the filled violet variant.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fg: Color = prominent ? .white : (destructive ? Theme.red : Theme.text)
        let bg: Color = prominent ? (destructive ? Theme.red : Theme.accent) : Theme.card
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 9 : 12)
            .frame(height: compact ? 24 : 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bg)
                    .brightness(configuration.isPressed ? -0.06 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(prominent ? 0.12 : 0.04), radius: 1.5, y: 1)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Segmented "tab pills" like Overzicht / Adviesflows / Producten.
struct PillTabs<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Theme.card : Color.clear)
                                .shadow(color: .black.opacity(selected ? 0.06 : 0), radius: 1, y: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.graySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct SoftBadge: View {
    let text: String
    var color: Color = Theme.secondaryText
    var background: Color = Theme.graySoft

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Square status icon for a changed file.
struct FileStatusIcon: View {
    let kind: FileStatusKind

    var body: some View {
        let (symbol, color, bg) = style
        Image(systemName: symbol)
            .font(.system(size: 8.5, weight: .heavy))
            .foregroundStyle(color)
            .frame(width: 17, height: 17)
            .background(bg, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            .help(label)
    }

    private var style: (String, Color, Color) {
        switch kind {
        case .modified, .typeChanged: return ("pencil", Theme.orange, Theme.orangeSoft)
        case .added: return ("plus", Theme.green, Theme.greenSoft)
        case .deleted: return ("minus", Theme.red, Theme.redSoft)
        case .renamed, .copied: return ("arrow.right", Theme.blue, Theme.blueSoft)
        case .untracked: return ("questionmark", Theme.secondaryText, Theme.graySoft)
        case .conflicted: return ("exclamationmark", .white, Theme.red)
        case .unknown: return ("circle", Theme.secondaryText, Theme.graySoft)
        }
    }

    private var label: String {
        switch kind {
        case .modified: return "Modified"
        case .typeChanged: return "Type changed"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .untracked: return "Untracked"
        case .conflicted: return "Conflicted"
        case .unknown: return "Changed"
        }
    }
}

struct AvatarView: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let hue = Double(abs(name.hashValue % 360)) / 360
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.85),
                                                  Color(hue: hue, saturation: 0.7, brightness: 0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
    }
}

/// Lets the user drag the window from custom chrome (the title bar is hidden).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.performZoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = 220

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: 28)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}
