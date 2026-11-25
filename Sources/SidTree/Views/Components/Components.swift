import AppKit
import SwiftUI

// MARK: - Logo

struct LogoMark: View {
    var size: CGFloat = 30
    var body: some View {
        if let logo = AppInfo.logo {
            Image(nsImage: logo).resizable().interpolation(.high).antialiased(true).scaledToFit()
                .frame(width: size * 0.62, height: size * 0.82)
                .frame(width: size, height: size)
                .background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        } else {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.action, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        }
    }
}

// MARK: - Buttons

/// Bordered button with a hover state. `prominent` gives the filled violet variant.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent, destructive: destructive, compact: compact)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let destructive: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        let fg: Color = prominent ? .white : (destructive ? Theme.red : Theme.text)
        let bg: Color = prominent ? (destructive ? Theme.destructiveAction : Theme.action) : (hover && isEnabled ? Theme.controlHover : Theme.card)
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: prominent ? .semibold : .regular))
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 9 : 11)
            .frame(height: compact ? 24 : 30)
            .background(
                RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                    .fill(bg)
                    .brightness(configuration.isPressed ? -0.05 : (prominent && hover && isEnabled ? 0.04 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.controlBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .handCursor(isEnabled)
    }
}

/// Borderless text button that shows a soft background on hover ("Unstage all", "Stage hunk").
struct TextButtonStyle: ButtonStyle {
    var color: Color = Theme.secondaryText
    var hoverFill: Color = Theme.pressFill
    var size: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        TextButtonBody(configuration: configuration, color: color, hoverFill: hoverFill, size: size)
    }
}

private struct TextButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let color: Color
    let hoverFill: Color
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: size))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(hover && isEnabled ? hoverFill : .clear))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .handCursor(isEnabled)
    }
}

/// Segmented control: "All branches | Current".
struct PillTabs<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(selected ? Theme.controlHover : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .handCursor()
            }
        }
        .padding(2)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .fixedSize()
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

/// Quiet count next to a section title ("STAGED  ⟮4⟯"), so number and label read as separate things.
struct SectionCount: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(Theme.graySoft))
    }
}

/// Round count badge: filled when there is something to report, outlined at zero.
struct CountBadge: View {
    let count: Int
    var fill: Color = Theme.action
    var textColor: Color = .white
    var showsZero = false

    var body: some View {
        if count >= 1 {
            Text(count > 999 ? "999+" : "\(count)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(textColor)
                .padding(.horizontal, 6)
                .frame(minWidth: 18, minHeight: 17)
                .background(Capsule().fill(fill))
        } else if showsZero {
            Text("0")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 16)
                .overlay(Capsule().strokeBorder(Theme.badgeBorder, lineWidth: 1))
        }
    }
}

/// Square status icon for a changed file (pencil, plus, minus …), coloured by kind.
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
        case .added, .untracked: return ("plus", Theme.green, Theme.greenSoft)
        case .deleted: return ("minus", Theme.red, Theme.redSoft)
        case .renamed, .copied: return ("arrow.right", Theme.blue, Theme.blueSoft)
        case .conflicted: return ("exclamationmark", .white, Theme.destructiveAction)
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
        case .untracked: return "New file (not tracked yet)"
        case .conflicted: return "Conflicted"
        case .unknown: return "Changed"
        }
    }
}

/// Small square checkbox: filled violet with a tick when on.
struct CheckBox: View {
    let checked: Bool
    var size: CGFloat = 15

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(checked ? Theme.action : Color.clear)
            .overlay {
                if checked {
                    Image(systemName: "checkmark").font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.white)
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Theme.checkboxBorder, lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
    }
}

struct AvatarView: View {
    let name: String
    var size: CGFloat = 30

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Theme.avatarText)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.avatarFill))
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
    var height: CGFloat = 28
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .handCursor()
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: height)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(focused ? Theme.action : Theme.controlBorder, lineWidth: 1))
    }
}

// MARK: - Pointer

extension View {
    /// Shows the pointing-hand cursor over anything that can be clicked.
    func handCursor(_ enabled: Bool = true) -> some View { modifier(HandCursor(enabled: enabled)) }
}

private struct HandCursor: ViewModifier {
    let enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(enabled ? .link : nil)
        } else {
            content
                .onHover { inside in
                    if inside && enabled && !pushed {
                        NSCursor.pointingHand.push()
                        pushed = true
                    } else if !inside && pushed {
                        NSCursor.pop()
                        pushed = false
                    }
                }
                .onDisappear {
                    if pushed { NSCursor.pop(); pushed = false }
                }
        }
    }
}
