import AppKit
import SwiftUI

struct ChangesView: View {
    @Bindable var model: RepoModel
    @AppStorage("changes.columnWidth") private var columnWidth: Double = 400
    @State private var stagedSelection: Set<String> = []
    @State private var unstagedSelection: Set<String> = []
    /// The list ⌘A applies to: the one clicked last.
    @State private var activeList = ActiveList.unstaged
    @State private var keyMonitor: Any?
    @AppStorage("split.changes.lists") private var listSplit = 0.5
    @AppStorage("split.changes.commit") private var commitSplit = 0.72
    /// Filters both lists by path; the list actions then apply to the files shown.
    @State private var query = ""

    private enum ActiveList { case staged, unstaged }
    @State private var dropOnStaged = false
    @State private var dropOnUnstaged = false

    var body: some View {
        VStack(spacing: 0) {
            if model.repoState != .normal { stateBanner }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Changes").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        SectionCount(text: "\(model.changeCount)")
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            .help(model.changeCount == 1 ? "1 changed file" : "\(model.changeCount) changed files")
                        Spacer(minLength: 8)
                        SearchField(placeholder: "Search files", text: $query, width: 170, height: 26)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            .help("Search staged and unstaged files by name")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    // Drag the line above the commit box to give the message more or less room.
                    SplitPane(axis: .vertical, fraction: $commitSplit, minFirst: 140, minSecond: 150, divider: true) {
                        fileLists
                    } second: {
                        CommitBox(model: model)
                    }
                }
                .frame(width: columnWidth)
                .background(Theme.column)
                ColumnResizeHandle(width: $columnWidth, range: 300...640)
                DiffView(file: model.selectedStatusFile, diff: model.statusDiff,
                         context: diffContext,
                         fileAction: fileAction,
                         onHunk: { action, hunk in
                             if let diff = model.statusDiff { model.hunkAction(action, hunk: hunk, in: diff) }
                         },
                         openLine: model.selectedStatusFile.flatMap { file in
                             file.kind == .deleted ? nil : { model.openInEditor(path: file.path, line: $0) }
                         },
                         editorName: model.editorName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
            }
        }
        .onAppear(perform: installSelectAllShortcut)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Lists

    private func matches(_ file: FileChange) -> Bool {
        query.isEmpty || file.path.localizedCaseInsensitiveContains(query)
            || (file.originalPath?.localizedCaseInsensitiveContains(query) ?? false)
    }
    private var staged: [FileChange] { model.status.staged.filter(matches) }
    private var unstaged: [FileChange] { model.status.unstaged.filter(matches) }

    private func countText(_ shown: Int, of total: Int) -> String { query.isEmpty ? "\(total)" : "\(shown)/\(total)" }

    /// Staged and unstaged each scroll on their own, so both headers and lists stay in view.
    /// The split follows the content: a short list only takes what it needs, and the line between
    /// them can be dragged when both are long.
    private var fileLists: some View {
        let header: CGFloat = 34
        func height(_ count: Int) -> CGFloat {
            header + (count == 0 ? 44 : CGFloat(count) * FileListMetrics.rowHeight + FileListMetrics.padding * 2)
        }
        let stagedHeight = height(staged.count), unstagedHeight = height(unstaged.count)
        let minimum = header + FileListMetrics.rowHeight * 2 + FileListMetrics.padding * 2
        return SplitPane(axis: .vertical, fraction: $listSplit,
                         minFirst: min(stagedHeight, minimum), minSecond: min(unstagedHeight, minimum),
                         maxFirst: stagedHeight, maxSecond: unstagedHeight, divider: true) {
            VStack(spacing: 0) {
                ListHeader(title: "Staged", count: countText(staged.count, of: model.status.staged.count)) {
                    Button("Unstage all") { if query.isEmpty { model.unstageAll() } else { model.unstage(staged) } }
                        .buttonStyle(TextButtonStyle())
                        .disabled(staged.isEmpty)
                }
                stagedList
            }
            .overlay(dropHighlight(dropOnStaged, text: "Drop to stage"))
            .dropDestination(for: FileDragPayload.self) { items, _ in
                handleDrop(items, toStaged: true)
            } isTargeted: { dropOnStaged = $0 }
        } second: {
            VStack(spacing: 0) {
                ListHeader(title: "Unstaged", count: countText(unstaged.count, of: model.status.unstaged.count)) {
                    Button("Discard") { model.discard(unstaged) }
                        .buttonStyle(TextButtonStyle(color: Theme.red, hoverFill: Theme.destructiveHover))
                        .disabled(unstaged.isEmpty)
                        .help("Discard all unstaged changes")
                    Button("Stage all") { if query.isEmpty { model.stageAll() } else { model.stage(unstaged) } }
                        .buttonStyle(TextButtonStyle(color: Theme.accent, hoverFill: Theme.accentHover))
                        .disabled(unstaged.isEmpty)
                }
                unstagedList
            }
            .overlay(dropHighlight(dropOnUnstaged, text: "Drop to unstage"))
            .dropDestination(for: FileDragPayload.self) { items, _ in
                handleDrop(items, toStaged: false)
            } isTargeted: { dropOnUnstaged = $0 }
        }
    }

    @ViewBuilder
    private var stagedList: some View {
        if staged.isEmpty {
            emptyState(!query.isEmpty ? "No staged files match" : (unstaged.isEmpty ? "Nothing to commit" : "Nothing staged yet — tick a file below"))
        } else {
            FileListView(files: staged, selection: $stagedSelection,
                         checkbox: true,
                         onSelect: { file in
                             activeList = .staged
                             unstagedSelection = []
                             model.selectStatusFile(file)
                         },
                         onToggle: { model.unstage([$0]) },
                         onDoubleClick: { model.unstage([$0]) },
                         dragKind: "staged",
                         dragRoot: model.root,
                         onToggleSelection: { model.unstage($0) }) { file in
                let targets = selected(file, in: staged, selection: stagedSelection)
                Button(targets.count > 1 ? "Unstage \(targets.count) Files" : "Unstage") { model.unstage(targets) }
                Divider()
                fileMenu(file, targets: targets)
            }
        }
    }

    @ViewBuilder
    private var unstagedList: some View {
        if unstaged.isEmpty {
            emptyState(query.isEmpty ? "Working copy is clean" : "No unstaged files match")
        } else {
            FileListView(files: unstaged, selection: $unstagedSelection,
                         checkbox: false,
                         onSelect: { file in
                             activeList = .unstaged
                             stagedSelection = []
                             model.selectStatusFile(file)
                         },
                         onToggle: { model.stage([$0]) },
                         onDoubleClick: { model.stage([$0]) },
                         dragKind: "unstaged",
                         dragRoot: model.root,
                         onToggleSelection: { model.stage($0) }) { file in
                let targets = selected(file, in: unstaged, selection: unstagedSelection)
                Button(targets.count > 1 ? "Stage \(targets.count) Files" : "Stage") { model.stage(targets) }
                if file.kind == .conflicted {
                    Divider()
                    Button("Resolve Using Mine (ours)") {
                        model.perform("Resolving") { try await model.git.resolve(file.path, ours: true) }
                    }
                    Button("Resolve Using Theirs") {
                        model.perform("Resolving") { try await model.git.resolve(file.path, ours: false) }
                    }
                    Button("Mark Resolved") { model.stage([file]) }
                }
                Divider()
                Button(targets.count > 1 ? "Discard \(targets.count) Files…" : "Discard Changes…", role: .destructive) {
                    model.discard(targets)
                }
                Divider()
                fileMenu(file, targets: targets)
            }
        }
    }

    /// "Stage file" / "Unstage file" for the file shown in the diff.
    private var fileAction: (title: String, action: () -> Void)? {
        guard let file = model.selectedStatusFile else { return nil }
        if file.staged { return ("Unstage file", { model.unstage([file]) }) }
        return (file.kind == .conflicted ? "Mark resolved" : "Stage file", { model.stage([file]) })
    }

    @ViewBuilder
    private func fileMenu(_ file: FileChange, targets: [FileChange]) -> some View {
        Button("Open") { model.open(file) }
        Button("Open in \(model.editorName)") { model.openInEditor(targets.filter { $0.kind != .deleted }) }
            .disabled(file.kind == .deleted)
        Button("Show in Finder") { model.reveal(file) }
        Button("Copy Path") { model.copyToPasteboard(file.path) }
        // A path with a line break cannot be written as one ignore rule; it would add unrelated rules.
        if file.kind == .untracked, !file.path.contains(where: \.isNewline) {
            Button("Add to .gitignore") {
                let line = "/" + file.path
                model.perform("Updating .gitignore") {
                    let url = model.root.appendingPathComponent(".gitignore")
                    var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
                    text += line + "\n"
                    try text.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    /// Which hunk actions the diff offers for the selected file.
    private var diffContext: DiffContext {
        guard let file = model.selectedStatusFile else { return .readOnly }
        if file.staged { return .staged }
        return file.kind == .untracked || file.kind == .conflicted ? .readOnly : .unstaged
    }

    /// ⌘A selects all files of the active list, unless a text field is being edited (it keeps its own ⌘A).
    /// Handled at key-event level because the standard Edit → Select All menu item would win otherwise.
    private func installSelectAllShortcut() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "a",
                  event.window?.isKeyWindow == true,
                  !(event.window?.firstResponder is NSText) else { return event }
            let staged = self.staged, unstaged = self.unstaged
            if activeList == .staged && !staged.isEmpty || unstaged.isEmpty {
                guard !staged.isEmpty else { return event }
                activeList = .staged
                unstagedSelection = []
                stagedSelection = Set(staged.map(\.id))
            } else {
                stagedSelection = []
                unstagedSelection = Set(unstaged.map(\.id))
            }
            return nil
        }
    }

    private func handleDrop(_ items: [FileDragPayload], toStaged: Bool) -> Bool {
        let source = toStaged ? "unstaged" : "staged"
        let paths = FileDragPayload.paths(in: items, from: source, root: model.root)
        let files = (toStaged ? unstaged : staged).filter { paths.contains($0.path) }
        guard !files.isEmpty else { return false }
        if toStaged {
            model.stage(files)
            unstagedSelection = []
        } else {
            model.unstage(files)
            stagedSelection = []
        }
        return true
    }

    @ViewBuilder
    private func dropHighlight(_ active: Bool, text: String) -> some View {
        if active {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(alignment: .bottom) {
                    Text(text)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.action, in: Capsule())
                        .padding(.bottom, 12)
                }
                .allowsHitTesting(false)
        }
    }

    private func selected(_ file: FileChange, in files: [FileChange], selection: Set<String>) -> [FileChange] {
        if selection.contains(file.id) && selection.count > 1 {
            return files.filter { selection.contains($0.id) }
        }
        return [file]
    }

    private func emptyState(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.mutedText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .contentShape(Rectangle())
    }

    private var stateBanner: some View {
        let (title, detail): (String, String) = {
            switch model.repoState {
            case .merging: return ("Merge in progress", "Resolve conflicts, stage the files and commit to finish the merge.")
            case .rebasing: return ("Rebase in progress", "Resolve conflicts, stage the files and continue the rebase.")
            case .cherryPicking: return ("Cherry-pick in progress", "Resolve conflicts, stage the files and commit.")
            case .reverting: return ("Revert in progress", "Resolve conflicts, stage the files and commit.")
            case .normal: return ("", "")
            }
        }()
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if !model.status.conflicted.isEmpty {
                SoftBadge(text: "\(model.status.conflicted.count) conflicted", color: Theme.red, background: Theme.redSoft)
            }
            if model.repoState == .rebasing {
                Button("Continue Rebase") { model.continueRebase() }.buttonStyle(PillButtonStyle(prominent: true))
            }
            Button("Abort") { model.abortOperation() }.buttonStyle(PillButtonStyle(destructive: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.orangeSoft)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// Sticky "STAGED 11 … Unstage all" header above a file list.
private struct ListHeader<Actions: View>: View {
    let title: String
    let count: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(Theme.secondaryText)
            SectionCount(text: count)
                .padding(.leading, 6)
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Theme.column)
    }
}
