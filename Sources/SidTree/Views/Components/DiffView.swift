import AppKit
import SwiftUI

enum DiffStyle {
    /// Each hunk in its own bordered card (Changes).
    case cards
    /// Hunk titles inline, no cards (commit details).
    case flat
}

struct DiffView: View {
    let file: FileChange?
    let diff: FileDiff?
    let context: DiffContext
    var style: DiffStyle = .cards
    /// Shows the file header with +/− counts and `fileAction`.
    var showsHeader = true
    var fileAction: (title: String, action: () -> Void)?
    var onHunk: ((RepoModel.HunkAction, DiffHunk) -> Void)?
    /// Right-click → "Open in <editor> at line N". Nil hides the item.
    var openLine: ((Int) -> Void)?
    var editorName = "Editor"

    @State private var forceLarge = false
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let charWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: font]).width

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader, file != nil { header }
            content
        }
        .onChange(of: file?.id) { _, _ in forceLarge = false }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let file {
                FileStatusIcon(kind: file.kind)
                Text(file.path)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                if let images = diff?.images {
                    ByteDelta(images: images)
                } else if let diff, !diff.isBinary, !diff.tooLarge {
                    if diff.added > 0 { Text("+\(diff.added)").foregroundStyle(Theme.addedText) }
                    if diff.removed > 0 { Text("−\(diff.removed)").foregroundStyle(Theme.removedText) }
                }
                Spacer(minLength: 8)
                if let fileAction {
                    Button(fileAction.title, action: fileAction.action)
                        .buttonStyle(PillButtonStyle(compact: true))
                }
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        if file == nil {
            placeholder("No file selected", detail: "Select a file to see its changes")
        } else if let diff {
            if let images = diff.images {
                ImageCompareView(images: images, compact: style == .flat)
            } else if diff.tooLarge {
                placeholder("This diff is too large to display", detail: nil)
            } else if diff.isBinary {
                placeholder("Binary file", detail: "No text changes to show")
            } else if diff.hunks.isEmpty {
                placeholder("No changes to show", detail: nil)
            } else if diff.lineCount > 15000 && !forceLarge {
                VStack(spacing: 10) {
                    placeholder("Large diff (\(diff.lineCount) lines)", detail: nil).frame(maxHeight: 60)
                    Button("Show anyway") { forceLarge = true }.buttonStyle(PillButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffBody(diff: diff, context: context, style: style, onHunk: onHunk, openLine: openLine, editorName: editorName)
                    .id(file?.id)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholder(_ text: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Theme.tertiaryText) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiffBody: View {
    let diff: FileDiff
    let context: DiffContext
    let style: DiffStyle
    let onHunk: ((RepoModel.HunkAction, DiffHunk) -> Void)?
    let openLine: ((Int) -> Void)?
    let editorName: String

    /// Lines per horizontally scrolling block: keeps huge hunks lazy while each card scrolls sideways on its own.
    private static let chunkSize = 200

    private struct Chunk: Identifiable {
        let id: String
        let lines: ArraySlice<DiffLine>
        let maxLength: Int
        let last: Bool
    }

    /// One flat list with stable, unique ids keeps LazyVStack recycling correct.
    private enum Item: Identifiable {
        case hunk(DiffHunk)
        case chunk(Chunk)
        case end(Int)
        var id: String {
            switch self {
            case .hunk(let h): return "h\(h.id)"
            case .chunk(let c): return c.id
            case .end(let h): return "e\(h)"
            }
        }
    }

    private var items: [Item] {
        var out: [Item] = []
        for h in diff.hunks {
            out.append(.hunk(h))
            var start = 0
            while start < h.lines.count {
                let end = min(start + Self.chunkSize, h.lines.count)
                let slice = h.lines[start..<end]
                let longest = slice.reduce(0) { max($0, $1.text.count) }
                out.append(.chunk(Chunk(id: "c\(h.id)-\(start)", lines: slice, maxLength: longest, last: end == h.lines.count)))
                start = end
            }
            if style == .cards { out.append(.end(h.id)) }
        }
        return out
    }

    /// Line-number columns sized to the largest number; a column that is empty throughout
    /// (a new or deleted file) is left out.
    private var metrics: DiffMetrics {
        var m: DiffMetrics = style == .cards ? .cards : .flat
        var maxOld = 0, maxNew = 0
        for h in diff.hunks {
            maxOld = max(maxOld, h.oldStart + h.oldCount)
            maxNew = max(maxNew, h.newStart + h.newCount)
        }
        let hasOld = diff.hunks.contains { $0.oldCount > 0 }
        let hasNew = diff.hunks.contains { $0.newCount > 0 }
        let digits = max(String(max(maxOld, maxNew)).count, 2)
        let width = (CGFloat(digits) * DiffView.charWidth + 12).rounded(.up)
        m.oldWidth = hasOld ? width : 0
        m.newWidth = hasNew ? width : 0
        return m
    }

    @State private var selection = LineSelection()
    @FocusState private var focused: Bool
    /// Room for an always-visible scroll bar (mouse attached, or "Show scroll bars: Always").
    @State private var scrollerWidth = Self.currentScrollerWidth

    static var currentScrollerWidth: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    var body: some View {
        GeometryReader { geo in
            let m = metrics
            let width = max(geo.size.width - m.outerPadding * 2 - scrollerWidth, 200)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .hunk(let hunk):
                            HunkHeader(hunk: hunk, index: hunk.id + 1, context: context, style: style, onHunk: onHunk)
                                .frame(width: width, alignment: .leading)
                                .padding(.top, style == .cards && hunk.id > 0 ? 12 : 0)
                        case .chunk(let chunk):
                            ChunkView(lines: chunk.lines, maxLength: chunk.maxLength, width: width, metrics: m,
                                      carded: style == .cards, selection: selection,
                                      openLine: openLine, editorName: editorName,
                                      onPress: { focused = true },
                                      copy: { line, markers in copy(around: line, markers: markers) })
                                .padding(.bottom, style == .flat && chunk.last ? 6 : 0)
                        case .end:
                            CardBottom()
                                .frame(width: width, height: 5)
                        }
                    }
                }
                .padding(.horizontal, m.outerPadding)
                .padding(.top, m.topPadding)
                .padding(.bottom, 24)
                // Short diffs start at the top instead of being centred in the scroll view. The width leaves room
                // for a legacy scroll bar; filling the full width would push that bar out of view.
                .frame(width: geo.size.width - scrollerWidth, alignment: .leading)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
                scrollerWidth = Self.currentScrollerWidth
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onCopyCommand {
            let text = selectedText(markers: false)
            return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
        }
        .onExitCommand { selection.clear() }
    }

    private var allLines: [DiffLine] { diff.hunks.flatMap(\.lines) }

    /// Selected lines in order; copying text never includes line numbers.
    private func selectedText(markers: Bool) -> String {
        allLines.filter { selection.ids.contains($0.id) }
            .map { line in
                guard markers else { return line.text }
                switch line.kind {
                case .added: return "+" + line.text
                case .removed: return "-" + line.text
                case .context: return " " + line.text
                case .noNewline: return line.text
                }
            }
            .joined(separator: "\n")
    }

    /// Right-click copies the selection, or just the clicked line when it is not part of it.
    private func copy(around line: DiffLine, markers: Bool) {
        if !selection.ids.contains(line.id) { selection.select(line.id) }
        let text = selectedText(markers: markers)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Selected diff lines: click, ⇧-click for a range, ⌘-click to add or remove, drag to select.
@MainActor
@Observable
final class LineSelection {
    private(set) var ids: Set<Int> = []
    private var anchor: Int?

    func select(_ id: Int) {
        ids = [id]
        anchor = id
    }

    func click(_ id: Int, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor {
            ids = Set(min(anchor, id)...max(anchor, id))
        } else if modifiers.contains(.command) {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
        } else {
            select(id)
        }
    }

    func drag(from start: Int, to end: Int) {
        ids = Set(min(start, end)...max(start, end))
        anchor = start
    }

    func clear() {
        ids = []
        anchor = nil
    }
}

/// A block of diff lines that scrolls sideways inside its card.
private struct ChunkView: View {
    let lines: ArraySlice<DiffLine>
    let maxLength: Int
    let width: CGFloat
    let metrics: DiffMetrics
    let carded: Bool
    let selection: LineSelection
    let openLine: ((Int) -> Void)?
    let editorName: String
    let onPress: () -> Void
    let copy: (DiffLine, Bool) -> Void
    @State private var dragStart: Int?

    var body: some View {
        let inner = carded ? width - 2 : width
        let contentWidth = max(inner, metrics.gutter + CGFloat(maxLength) * DiffView.charWidth + 16)
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    DiffLineRow(line: line, width: contentWidth, metrics: metrics, selected: selection.ids.contains(line.id))
                        .contextMenu {
                            Button("Copy") { copy(line, false) }
                            Button("Copy with +/− Markers") { copy(line, true) }
                            if let openLine, let number = line.newLine ?? line.oldLine {
                                Divider()
                                Button("Open in \(editorName) at Line \(number)") { openLine(number) }
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let start = index(at: value.startLocation.y), let current = index(at: value.location.y) else { return }
                        let startID = lines[start].id, currentID = lines[current].id
                        if dragStart == nil {
                            dragStart = startID
                            onPress()
                            selection.click(startID, modifiers: NSEvent.modifierFlags)
                        } else if let dragStart, dragStart != currentID || selection.ids.count > 1 {
                            selection.drag(from: dragStart, to: currentID)
                        }
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .scrollDisabled(contentWidth <= inner)
        .handCursor(false)
        .frame(width: inner)
        .background(carded ? Theme.hunkBackground : .clear)
        .padding(.horizontal, carded ? 1 : 0)
        .overlay {
            if carded {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.border).frame(width: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(Theme.border).frame(width: 1)
                }
            }
        }
    }
}

extension ChunkView {
    fileprivate func index(at y: CGFloat) -> Int? {
        guard !lines.isEmpty else { return nil }
        let i = Int(floor(y / DiffMetrics.rowHeight))
        return lines.startIndex + min(max(i, 0), lines.count - 1)
    }
}

private struct DiffMetrics {
    var oldWidth: CGFloat
    var newWidth: CGFloat
    let signWidth: CGFloat
    let outerPadding: CGFloat
    let topPadding: CGFloat
    var gutter: CGFloat { oldWidth + newWidth + signWidth }
    static let rowHeight: CGFloat = 20

    static let cards = Self(oldWidth: 44, newWidth: 44, signWidth: 18, outerPadding: 16, topPadding: 12)
    static let flat = Self(oldWidth: 38, newWidth: 38, signWidth: 16, outerPadding: 0, topPadding: 8)
}

private struct HunkHeader: View {
    let hunk: DiffHunk
    let index: Int
    let context: DiffContext
    let style: DiffStyle
    let onHunk: ((RepoModel.HunkAction, DiffHunk) -> Void)?

    var body: some View {
        switch style {
        case .cards: card
        case .flat: flat
        }
    }

    private var card: some View {
        HStack(spacing: 10) {
            Text("Hunk \(index)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(linesText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.tertiaryText)
            Spacer(minLength: 8)
            actions(bordered: false)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.hunkHeader)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: 1))
    }

    /// Full-width bar: "Hunk 1 : Lines 286–296" with the action as a bordered button on the right.
    private var flat: some View {
        HStack(spacing: 8) {
            Text("Hunk \(index) : \(linesText)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            actions(bordered: true)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.hunkHeader)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private func actions(bordered: Bool) -> some View {
        if let onHunk {
            switch context {
            case .unstaged:
                hunkButton("Discard hunk", destructive: true, bordered: bordered) { onHunk(.discard, hunk) }
                hunkButton("Stage hunk", bordered: bordered) { onHunk(.stage, hunk) }
            case .staged:
                hunkButton("Unstage hunk", bordered: bordered) { onHunk(.unstage, hunk) }
            case .commit:
                hunkButton("Reverse hunk", bordered: bordered) { onHunk(.reverse, hunk) }
            case .readOnly:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func hunkButton(_ title: String, destructive: Bool = false, bordered: Bool, action: @escaping () -> Void) -> some View {
        if bordered {
            Button(title, action: action).buttonStyle(PillButtonStyle(destructive: destructive, compact: true))
        } else if destructive {
            Button(title, action: action).buttonStyle(TextButtonStyle(color: Theme.red, hoverFill: Theme.destructiveHover))
        } else {
            Button(title, action: action).buttonStyle(TextButtonStyle())
        }
    }

    /// New-file line range; a hunk that only removes lines (a deleted file) shows its old range.
    private var linesText: String {
        let (start, count) = hunk.newCount > 0 ? (hunk.newStart, hunk.newCount) : (hunk.oldStart, hunk.oldCount)
        return "Lines \(start)–\(start + max(count - 1, 0))"
    }
}

/// Rounded bottom of a hunk card: side and bottom border, no top edge.
private struct CardBottom: View {
    var body: some View {
        BottomCapShape()
            .fill(Theme.hunkBackground)
            .overlay(BottomCapShape(open: true).stroke(Theme.border, lineWidth: 1))
    }
}

private struct BottomCapShape: Shape {
    var open = false
    var radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        let rad = min(radius, r.height)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: rect.minY - (open ? 0.5 : 0)))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + rad, y: r.maxY), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - rad), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: rect.minY - (open ? 0.5 : 0)))
        if !open { p.closeSubpath() }
        return p
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let width: CGFloat
    let metrics: DiffMetrics
    var selected = false

    var body: some View {
        HStack(spacing: 0) {
            if metrics.oldWidth > 0 {
                Text(line.oldLine.map(String.init) ?? "")
                    .padding(.trailing, 6)
                    .frame(width: metrics.oldWidth, alignment: .trailing)
            }
            if metrics.newWidth > 0 {
                Text(line.newLine.map(String.init) ?? "")
                    .padding(.trailing, 6)
                    .frame(width: metrics.newWidth, alignment: .trailing)
            }
            Text(marker)
                .frame(width: metrics.signWidth, alignment: .center)
                .foregroundStyle(markerColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .noNewline ? Theme.tertiaryText : Theme.diffText)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(Font(DiffView.font))
        .foregroundStyle(Theme.mutedText)
        .frame(width: width, height: DiffMetrics.rowHeight, alignment: .leading)
        .background(selected ? Theme.selection : .clear)
        .background(background)
    }

    private var marker: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        default: return ""
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .added: return Theme.addedText
        case .removed: return Theme.removedText
        default: return Theme.tertiaryText
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: return Theme.addedBg
        case .removed: return Theme.removedBg
        default: return .clear
        }
    }
}
