import AppKit
import SwiftUI

/// Selectable list of changed files. Supports ⌘-click and ⇧-click multi-selection.
struct FileListView<Menu: View>: View {
    let files: [FileChange]
    let focused: FileChange?
    @Binding var selection: Set<String>
    var checkbox: Bool? = nil          // nil: no checkbox; true: checked (staged); false: unchecked
    var onSelect: (FileChange) -> Void
    var onToggle: ((FileChange) -> Void)? = nil
    var onDoubleClick: ((FileChange) -> Void)? = nil
    @ViewBuilder var menu: (FileChange) -> Menu

    @State private var anchor: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(files) { file in
                    FileRow(file: file,
                            selected: selection.contains(file.id),
                            focused: focused?.id == file.id,
                            checkbox: checkbox,
                            onToggle: { onToggle?(file) })
                        .onTapGesture(count: 2) { onDoubleClick?(file) }
                        .simultaneousGesture(TapGesture().onEnded { click(file) })
                        .contextMenu { menu(file) }
                }
            }
            .padding(6)
        }
    }

    private func click(_ file: FileChange) {
        let flags = NSEvent.modifierFlags
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Theme.selection : (hover ? Theme.subtle : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(file.path)
    }
}
