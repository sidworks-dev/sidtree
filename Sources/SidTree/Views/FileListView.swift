import AppKit
import SwiftUI

/// Selectable files with click, modifier-click and Finder-style marquee selection.
struct FileListView<Menu: View>: View {
    let files: [FileChange]
    let focused: FileChange?
    @Binding var selection: Set<String>
    var checkbox: Bool? = nil          // nil: no checkbox; true: checked (staged); false: unchecked
    var onSelect: (FileChange) -> Void
    var onToggle: ((FileChange) -> Void)? = nil
    var onDoubleClick: ((FileChange) -> Void)? = nil
    /// When set, rows can be dragged to the other list ("staged" or "unstaged").
    var dragKind: String? = nil
    @ViewBuilder var menu: (FileChange) -> Menu

    @State private var anchor: String?

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                LazyVStack(spacing: FileListMetrics.spacing) {
                    ForEach(files) { file in
                        FileRow(file: file,
                                selected: selection.contains(file.id),
                                focused: focused?.id == file.id,
                                checkbox: checkbox,
                                onToggle: { onToggle?(file) })
                            .onTapGesture(count: 2) { onDoubleClick?(file) }
                            .simultaneousGesture(TapGesture().onEnded { click(file) })
                            .contextMenu { menu(file) }
                            .modifier(FileDragModifier(kind: dragKind, files: dragFiles(for: file)))
                    }
                }
                .padding(FileListMetrics.padding)
                .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                .overlayPreferenceValue(FileRowContentBounds.self) { anchors in
                    GeometryReader { geometry in
                        FileMarqueeSelection(ids: files.map(\.id), selection: $selection,
                                             contentFrames: anchors.mapValues { geometry[$0] },
                                             onClick: { index, flags in click(files[index], modifiers: flags) },
                                             onFinish: { index in
                                                 guard let index else { return }
                                                 anchor = files[index].id
                                                 onSelect(files[index])
                                             })
                    }
                }
            }
        }
        .onChange(of: files.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if let anchor, !ids.contains(anchor) { self.anchor = nil }
        }
    }

    /// Dragging a selected row drags the whole selection; otherwise just that row.
    private func dragFiles(for file: FileChange) -> [FileChange] {
        guard selection.contains(file.id), selection.count > 1 else { return [file] }
        return files.filter { selection.contains($0.id) }
    }

    private func click(_ file: FileChange, modifiers flags: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        if flags.contains(.command) {
            if selection.contains(file.id) { selection.remove(file.id) } else { selection.insert(file.id) }
            anchor = file.id
        } else if flags.contains(.shift), let anchor, let a = files.firstIndex(where: { $0.id == anchor }),
                  let b = files.firstIndex(where: { $0.id == file.id }) {
            selection = Set(files[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [file.id]
            anchor = file.id
        }
        onSelect(file)
    }
}

struct FileRow: View {
    let file: FileChange
    let selected: Bool
    let focused: Bool
    var checkbox: Bool?
    var onToggle: () -> Void = {}
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                if let checkbox {
                    Button(action: onToggle) {
                        Image(systemName: checkbox ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13))
                            .foregroundStyle(checkbox ? Theme.accent : Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(checkbox ? "Unstage" : "Stage")
                }
                FileStatusIcon(kind: file.kind)
                HStack(spacing: 5) {
                    Text(file.fileName)
                        .font(.system(size: 12.5, weight: focused ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let orig = file.originalPath {
                        Text("← \((orig as NSString).lastPathComponent)").font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                    Text(file.directory)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .anchorPreference(key: FileRowContentBounds.self, value: .bounds) { [file.id: $0] }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: FileListMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Theme.selection : (hover ? Theme.subtle : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(file.path)
    }
}

// MARK: - Drag and drop between the staged and unstaged lists

enum FileDragPayload {
    static let marker = "sidtree-files"

    static func encode(kind: String, paths: [String]) -> String {
        ([marker, kind] + paths).joined(separator: "\n")
    }

    /// Returns the source list ("staged"/"unstaged") and the paths, or nil for foreign drops.
    static func decode(_ text: String) -> (kind: String, paths: [String])? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 3, lines[0] == marker else { return nil }
        return (lines[1], Array(lines[2...]))
    }
}

struct FileDragModifier: ViewModifier {
    let kind: String?
    let files: [FileChange]

    func body(content: Content) -> some View {
        if let kind {
            content.draggable(FileDragPayload.encode(kind: kind, paths: files.map(\.path))) {
                HStack(spacing: 6) {
                    FileStatusIcon(kind: files.first?.kind ?? .modified)
                    Text(files.count == 1 ? files[0].fileName : "\(files.count) files")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.accent.opacity(0.6)))
            }
        } else {
            content
        }
    }
}
