import AppKit
import SwiftUI

struct DiffView: View {
    let file: FileChange?
    let diff: FileDiff?
    let context: DiffContext
    var onHunk: ((RepoModel.HunkAction, DiffHunk) -> Void)?

    @State private var forceLarge = false
    static let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    static let charWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: font]).width

    var body: some View {
        Card {
            VStack(spacing: 0) {
                header
                content
            }
        }
        .onChange(of: file?.id) { _, _ in forceLarge = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let file {
                FileStatusIcon(kind: file.kind)
                Text(file.path)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let diff, !diff.isBinary {
                    SoftBadge(text: "+\(diff.added)", color: Theme.addedText, background: Theme.addedBg)
                    SoftBadge(text: "−\(diff.removed)", color: Theme.removedText, background: Theme.removedBg)
                }
            } else {
                Text("Diff").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        if file == nil {
            placeholder("Select a file to see its changes", symbol: "doc.text.magnifyingglass")
        } else if let diff {
            if diff.tooLarge {
                placeholder("This diff is too large to display", symbol: "exclamationmark.triangle")
            } else if diff.isBinary {
                placeholder("Binary file", symbol: "doc.zipper")
            } else if diff.hunks.isEmpty {
                placeholder("No changes to show", symbol: "checkmark.circle")
            } else if diff.lineCount > 15000 && !forceLarge {
                VStack(spacing: 10) {
                    placeholder("Large diff (\(diff.lineCount) lines)", symbol: "doc.text")
                    Button("Show anyway") { forceLarge = true }.buttonStyle(PillButtonStyle())
                }
            } else {
                DiffBody(diff: diff, context: context, onHunk: onHunk)
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Theme.secondaryText.opacity(0.6))
            Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiffBody: View {
    let diff: FileDiff
    let context: DiffContext
    let onHunk: ((RepoModel.HunkAction, DiffHunk) -> Void)?

    /// One flat list with stable, unique ids keeps LazyVStack recycling correct.
    private enum Item: Identifiable {
        case hunk(DiffHunk)
        case line(DiffLine)
        var id: String {
            switch self {
            case .hunk(let h): return "h\(h.id)"
            case .line(let l): return "l\(l.id)"
            }
        }
    }

    private var items: [Item] {
        var out: [Item] = []
        out.reserveCapacity(diff.lineCount + diff.hunks.count)
        for h in diff.hunks {
            out.append(.hunk(h))
            for l in h.lines { out.append(.line(l)) }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let gutter: CGFloat = 98
            let contentWidth = max(geo.size.width, gutter + CGFloat(diff.maxLineLength) * DiffView.charWidth + 40)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .hunk(let hunk):
                            HunkHeader(hunk: hunk, index: hunk.id + 1, context: context, onHunk: onHunk)
                                .frame(width: contentWidth, alignment: .leading)
                        case .line(let line):
                            DiffLineRow(line: line, width: contentWidth)
                        }
                    }
                }
                .padding(.bottom, 8)
                // Short diffs start at the top instead of being centred in the scroll view.
                .frame(width: contentWidth, alignment: .leading)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
    }
}

private struct HunkHeader: View {
    let hunk: DiffHunk
    let index: Int
    let context: DiffContext
    let onHunk: ((RepoModel.HunkAction, DiffHunk) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text("Hunk \(index)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Lines \(hunk.newStart)–\(hunk.newStart + max(hunk.newCount - 1, 0))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Text(contextText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondaryText.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let onHunk {
                switch context {
                case .unstaged:
                    Button("Discard Hunk") { onHunk(.discard, hunk) }.buttonStyle(PillButtonStyle(destructive: true, compact: true))
                    Button("Stage Hunk") { onHunk(.stage, hunk) }.buttonStyle(PillButtonStyle(prominent: true, compact: true))
                case .staged:
                    Button("Unstage Hunk") { onHunk(.unstage, hunk) }.buttonStyle(PillButtonStyle(compact: true))
                case .commit:
                    Button("Reverse Hunk") { onHunk(.reverse, hunk) }.buttonStyle(PillButtonStyle(compact: true))
                case .readOnly:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.subtle)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var contextText: String {
        // Text after the closing @@ (function context).
        let parts = hunk.header.components(separatedBy: "@@")
        return parts.count >= 3 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
            Text(marker)
                .frame(width: 18, alignment: .center)
                .foregroundStyle(markerColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .noNewline ? Theme.secondaryText : Theme.text)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(Font(DiffView.font))
        .foregroundStyle(Theme.secondaryText.opacity(0.75))
        .frame(width: width, height: 18, alignment: .leading)
        .background(background)
        .textSelection(.enabled)
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
        default: return Theme.secondaryText
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
