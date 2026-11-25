import AppKit
import SwiftUI

/// Selectable files with click, modifier-click and Finder-style marquee selection.
struct FileListView<Menu: View>: View {
    let files: [FileChange]
    @Binding var selection: Set<String>
    var checkbox: Bool?          // nil: no checkbox; true: checked (staged); false: unchecked
    var onSelect: (FileChange) -> Void
    var onToggle: ((FileChange) -> Void)?
    var onDoubleClick: ((FileChange) -> Void)?
    /// When set, rows can be dragged to the other list ("staged" or "unstaged").
    var dragKind: String?
    var dragRoot: URL?
    /// Space bar: stage/unstage the selected files.
    var onToggleSelection: (([FileChange]) -> Void)?
    /// False when the list sits inside an outer scroll view together with other content.
    var scrolls = true
    /// Optional trailing text per row, e.g. "+9 −1".
    var detail: ((FileChange) -> String?)?
    var selectionFill: Color = Theme.selection
    @ViewBuilder var menu: (FileChange) -> Menu

    @State private var anchor: String?
    @State private var hoveredID: String?
    @State private var cursor: String?
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if scrolls {
                GeometryReader { viewport in
                    ScrollView { rows(minHeight: viewport.size.height) }
                }
            } else {
                rows(minHeight: 0)
            }
        }
        .onChange(of: files.map(\.id)) { _, ids in
            selection.formIntersection(ids)
            if let anchor, !ids.contains(anchor) { self.anchor = nil }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in move(-1, extend: press.modifiers.contains(.shift)) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in move(1, extend: press.modifiers.contains(.shift)) }
        .onKeyPress(.space) {
            let chosen = files.filter { selection.contains($0.id) }
            guard let onToggleSelection, !chosen.isEmpty else { return .ignored }
            onToggleSelection(chosen)
            return .handled
        }
    }

    private func rows(minHeight: CGFloat) -> some View {
        LazyVStack(spacing: FileListMetrics.spacing) {
            ForEach(files) { file in
                FileRow(file: file,
                        selected: selection.contains(file.id),
                        hovered: hoveredID == file.id,
                        checkbox: checkbox,
                        detail: detail?(file),
                        selectionFill: selectionFill,
                        onToggle: { onToggle?(file) })
                    .onTapGesture(count: 2) { onDoubleClick?(file) }
                    .simultaneousGesture(TapGesture().onEnded { click(file) })
                    .contextMenu { menu(file) }
            }
        }
        .padding(FileListMetrics.padding)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .overlayPreferenceValue(FileRowContentBounds.self) { anchors in
            GeometryReader { geometry in
                FileMarqueeSelection(ids: files.map(\.id), selection: $selection,
                                     contentFrames: anchors.content.mapValues { geometry[$0] },
                                     onClick: { index, flags in click(files[index], modifiers: flags) },
                                     onFinish: { index in
                                         guard let index else { return }
                                         anchor = files[index].id
                                         onSelect(files[index])
                                     },
                                     dragFrames: dragRoot != nil && dragKind != nil
                                         ? anchors.draggable.mapValues { geometry[$0] } : [:],
                                     onDoubleClick: { onDoubleClick?(files[$0]) },
                                     onDragItems: draggingItems,
                                     onHover: { index in hoveredID = index.flatMap { files.indices.contains($0) ? files[$0].id : nil } })
            }
        }
    }

    /// ↑/↓ move the selection, ⇧ extends it from the anchor.
    private func move(_ delta: Int, extend: Bool) -> KeyPress.Result {
        guard !files.isEmpty else { return .ignored }
        let start = cursor.flatMap { id in files.firstIndex { $0.id == id } }
            ?? files.firstIndex { selection.contains($0.id) }
            ?? (delta > 0 ? -1 : files.count)
        let next = min(max(start + delta, 0), files.count - 1)
        let file = files[next]
        if extend, let anchor, let a = files.firstIndex(where: { $0.id == anchor }) {
            selection = Set(files[min(a, next)...max(a, next)].map(\.id))
        } else {
            selection = [file.id]
            anchor = file.id
        }
        cursor = file.id
        onSelect(file)
        return .handled
    }

    /// Dragging a selected row drags the whole selection; otherwise just that row.
    private func dragFiles(for file: FileChange) -> [FileChange] {
        guard selection.contains(file.id), selection.count > 1 else { return [file] }
        return files.filter { selection.contains($0.id) }
    }

    private func draggingItems(for index: Int) -> [NSDraggingItem] {
        guard let dragRoot, let dragKind, files.indices.contains(index) else { return [] }
        return FileDragPayload.draggingItems(root: dragRoot, kind: dragKind, files: dragFiles(for: files[index]))
    }

    private func click(_ file: FileChange, modifiers flags: NSEvent.ModifierFlags = NSEvent.modifierFlags) {
        listFocused = true
        cursor = file.id
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
    var hovered = false
    var checkbox: Bool?
    var detail: String?
    var selectionFill: Color = Theme.selection
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                if let checkbox {
                    Button(action: onToggle) {
                        CheckBox(checked: checkbox)
                            .frame(width: 18, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .help(checkbox ? "Unstage" : "Stage")
                }
                HStack(spacing: 9) {
                    FileStatusIcon(kind: file.kind)
                    HStack(spacing: 5) {
                        Text(file.path)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                        if let orig = file.originalPath {
                            Text("← \(orig)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .anchorPreference(key: FileRowContentBounds.self, value: .bounds) { FileRowBounds(draggable: [file.id: $0]) }
            }
            .transformAnchorPreference(key: FileRowContentBounds.self, value: .bounds) { $0.content[file.id] = $1 }
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: FileListMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? selectionFill : (hovered ? Theme.subtle : Color.clear))
        )
        .contentShape(Rectangle())
        .help(file.path)
    }
}
