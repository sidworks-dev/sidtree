import AppKit
import SwiftUI

struct FileStatusView: View {
    @Bindable var model: RepoModel
    @AppStorage("split.status.lists") private var listSplit = 0.4
    @AppStorage("split.status.diff") private var diffSplit = 0.36
    @AppStorage("split.status.commit") private var commitSplit = 0.78
    @State private var stagedSelection: Set<String> = []
    @State private var unstagedSelection: Set<String> = []
    /// The list ⌘A applies to: the one clicked last.
    @State private var activeList = ActiveList.unstaged
    @State private var keyMonitor: Any?

    private enum ActiveList { case staged, unstaged }
    @State private var dropOnStaged = false
    @State private var dropOnUnstaged = false

    var body: some View {
        VStack(spacing: 12) {
            if model.repoState != .normal { stateBanner }
            SplitPane(axis: .vertical, fraction: $commitSplit, minFirst: 220, minSecond: 120) {
                SplitPane(axis: .horizontal, fraction: $diffSplit, minFirst: 280, minSecond: 320) {
                    SplitPane(axis: .vertical, fraction: $listSplit, minFirst: 90, minSecond: 90) {
                        stagedCard
                            .overlay(dropHighlight(dropOnStaged, text: "Drop to stage"))
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items, toStaged: true)
                            } isTargeted: { dropOnStaged = $0 }
                    } second: {
                        unstagedCard
                            .overlay(dropHighlight(dropOnUnstaged, text: "Drop to unstage"))
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items, toStaged: false)
                            } isTargeted: { dropOnUnstaged = $0 }
                    }
                } second: {
                    DiffView(file: model.selectedStatusFile, diff: model.statusDiff,
                             context: diffContext,
                             onHunk: { action, hunk in
                                 if let diff = model.statusDiff { model.hunkAction(action, hunk: hunk, in: diff) }
                             })
                }
            } second: {
                CommitBox(model: model)
            }
        }
        .padding(16)
        .onAppear(perform: installSelectAllShortcut)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Cards

    private var stagedCard: some View {
        Card {
            VStack(spacing: 0) {
                CardHeader(title: "Staged files", subtitle: "\(model.status.staged.count)") {
                    Button("Unstage All") { model.unstageAll() }
                        .buttonStyle(PillButtonStyle(compact: true))
                        .disabled(model.status.staged.isEmpty)
                }
                if model.status.staged.isEmpty {
                    emptyState("Nothing staged yet", hint: "Tick a file below to stage it")
                } else {
                    FileListView(files: model.status.staged, focused: model.selectedStatusFile, selection: $stagedSelection,
                                 checkbox: true,
                                 onSelect: { file in
                                     activeList = .staged
                                     unstagedSelection = []
                                     model.selectStatusFile(file)
                                 },
                                 onToggle: { model.unstage([$0]) },
                                 onDoubleClick: { model.unstage([$0]) },
                                 dragKind: "staged",
                                 onToggleSelection: { model.unstage($0) }) { file in
                        let targets = selected(file, in: model.status.staged, selection: stagedSelection)
                        Button(targets.count > 1 ? "Unstage \(targets.count) Files" : "Unstage") { model.unstage(targets) }
                        Divider()
                        fileMenu(file, targets: targets)
                    }
                }
            }
        }
    }

    private var unstagedCard: some View {
        Card {
            VStack(spacing: 0) {
                CardHeader(title: "Unstaged files", subtitle: "\(model.status.unstaged.count)") {
                    Button("Discard All") { model.discard(model.status.unstaged) }
                        .buttonStyle(PillButtonStyle(destructive: true, compact: true))
                        .disabled(model.status.unstaged.isEmpty)
                    Button("Stage All") { model.stageAll() }
                        .buttonStyle(PillButtonStyle(prominent: true, compact: true))
                        .disabled(model.status.unstaged.isEmpty)
                }
                if model.status.unstaged.isEmpty {
                    emptyState("Working copy is clean", hint: nil)
                } else {
                    FileListView(files: model.status.unstaged, focused: model.selectedStatusFile, selection: $unstagedSelection,
                                 checkbox: false,
                                 onSelect: { file in
                                     activeList = .unstaged
                                     stagedSelection = []
                                     model.selectStatusFile(file)
                                 },
                                 onToggle: { model.stage([$0]) },
                                 onDoubleClick: { model.stage([$0]) },
                                 dragKind: "unstaged",
                                 onToggleSelection: { model.stage($0) }) { file in
                        let targets = selected(file, in: model.status.unstaged, selection: unstagedSelection)
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
        }
    }

    @ViewBuilder
    private func fileMenu(_ file: FileChange, targets: [FileChange]) -> some View {
        Button("Open") { model.open(file) }
        Button("Show in Finder") { model.reveal(file) }
        Button("Copy Path") { model.copyToPasteboard(file.path) }
        if file.kind == .untracked {
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
            let staged = model.status.staged, unstaged = model.status.unstaged
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

    private func handleDrop(_ items: [String], toStaged: Bool) -> Bool {
        let source = toStaged ? "unstaged" : "staged"
        let paths = Set(items.compactMap(FileDragPayload.decode).filter { $0.kind == source }.flatMap(\.paths))
        guard !paths.isEmpty else { return false }
        if toStaged {
            model.stage(model.status.unstaged.filter { paths.contains($0.path) })
            unstagedSelection = []
        } else {
            model.unstage(model.status.staged.filter { paths.contains($0.path) })
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

    private func emptyState(_ title: String, hint: String?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.secondaryText)
            if let hint { Text(hint).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText.opacity(0.8)) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .padding(12)
        .background(Theme.orangeSoft, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.orange.opacity(0.35), lineWidth: 1))
    }
}

struct CommitBox: View {
    @Bindable var model: RepoModel
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if model.commitMessage.isEmpty {
                        Text(model.status.staged.isEmpty ? "Stage files, then write a commit message…" : "Commit message (first line is the summary)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText.opacity(0.8))
                            .padding(.horizontal, 15)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.commitMessage)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .focused($focused)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 14) {
                    AIGenerateControl(model: model)
                    Rectangle().fill(Theme.border).frame(width: 1, height: 18)
                    Toggle("Amend last commit", isOn: $model.amend).toggleStyle(.checkbox)
                    Spacer()
                    let summary = model.commitMessage.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
                    if !summary.isEmpty {
                        Text("\(summary.count)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(summary.count > 72 ? Theme.orange : Theme.secondaryText)
                            .help("Summary length (keep under 72)")
                    }
                    CommitActionControl(model: model)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
            }
        }
        .onChange(of: model.commitFocusToken) { _, _ in focused = true }
        .onAppear { if model.commitFocusToken > 0 { focused = true } }
    }
}

/// The main button performs the remembered action; the arrow changes it without committing.
struct CommitActionControl: View {
    @Bindable var model: RepoModel
    @State private var hoverMain = false
    @State private var hoverMenu = false

    private var disabled: Bool { model.committing || !model.canCommit || (model.pushAfterCommit && model.currentBranch == nil) }
    private var title: String {
        if model.amend { return model.pushAfterCommit ? "Amend & Push" : "Amend Commit" }
        return model.pushAfterCommit ? "Commit & Push" : "Commit"
    }
    private var help: String {
        guard model.pushAfterCommit else { return "Commit staged changes (⌘Return)" }
        guard let branch = model.currentBranch else { return "Choose Commit or check out a branch before pushing" }
        let target = model.currentBranchInfo?.upstream ?? "\(model.remotes.first ?? "origin")/\(branch)"
        return "Commit and push to \(target) (⌘Return)"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { model.commit() } label: {
                Group {
                    if model.committing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).tint(.white).frame(width: 12, height: 12)
                            Text("Processing…")
                        }
                    } else {
                        Text(title)
                    }
                }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(hoverMain && !disabled ? .white.opacity(0.1) : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverMain = $0 }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(disabled)
            .opacity(model.committing ? 0.75 : (disabled ? 0.5 : 1))
            .help(model.committing ? "Committing…" : help)

            Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 18)
            Menu {
                Button("Commit") { model.pushAfterCommit = false }
                Button("Commit & Push") { model.pushAfterCommit = true }
                    .disabled(model.currentBranch == nil)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 30)
                    .background(hoverMenu ? .white.opacity(0.1) : .clear)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundColor(.white)
            .tint(.white)
            .fixedSize()
            .onHover { hoverMenu = $0 }
            .help("Choose Commit or Commit & Push; remembered for this repository")
            .accessibilityLabel("Commit action")
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.white)
        .background(Theme.action, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.accent.opacity(0.25)))
    }
}

/// "✨ Generate ▾" split button: generate, or switch provider/model and open the AI settings.
struct AIGenerateControl: View {
    let model: RepoModel
    @AppStorage(AISettings.provider) private var provider = AIProvider.off.rawValue
    @AppStorage(AISettings.claudeModel) private var claudeModel = ClaudeModel.haiku.rawValue
    @AppStorage(AISettings.codexModel) private var codexModel = ""
    @AppStorage("settings.tab") private var settingsTab = "general"
    @Environment(\.openSettings) private var openSettings
    @State private var hoverMain = false
    @State private var hoverMenu = false

    private var current: AIProvider { AIProvider(rawValue: provider) ?? .off }
    private var canGenerate: Bool { current != .off && (!model.status.staged.isEmpty || model.amend) }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if current == .off { showMenu() } else { model.generateCommitMessage() }
            } label: {
                HStack(spacing: 5) {
                    if model.aiGenerating {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                        Text("Generating…")
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                        Text(current == .off ? "AI" : "Generate")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(hoverMain ? Theme.subtle : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverMain = $0 }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(model.aiGenerating || (current != .off && !canGenerate))
            .opacity(model.aiGenerating ? 0.6 : (current != .off && !canGenerate ? 0.45 : 1))
            .help(current == .off ? "Set up AI commit messages" :
                    "Write a commit message with \(current.title) · \(modelLabel) (⌥⌘G). Text already in the box is used as your intent.")

            Rectangle().fill(Theme.border).frame(width: 1, height: 24)

            Button(action: showMenu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 20, height: 24)
                    .background(hoverMenu ? Theme.subtle : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverMenu = $0 }
            .help("Switch AI model or open AI settings")
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Theme.text)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
    }

    private var modelLabel: String {
        switch current {
        case .claude: return AISettings.currentClaudeModel.capitalized
        case .codex: return AISettings.currentCodexModel ?? "default"
        case .off: return ""
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        if model.aiGenerating {
            menu.addItem(ClosureMenuItem("Cancel Generating") { model.cancelCommitMessageGeneration() })
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: "Generate with"))
        for p in AIProvider.allCases {
            let item = ClosureMenuItem(p == .off ? "Off" : p.title) { provider = p.rawValue }
            item.state = current == p ? .on : .off
            menu.addItem(item)
        }
        switch current {
        case .claude:
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Claude model"))
            for m in ClaudeModel.allCases {
                let item = ClosureMenuItem(m.title) { claudeModel = m.rawValue }
                item.state = claudeModel == m.rawValue ? .on : .off
                menu.addItem(item)
            }
            if claudeModel == AISettings.customModelTag {
                let item = ClosureMenuItem("Custom: \(AISettings.currentClaudeModel)") {}
                item.state = .on
                menu.addItem(item)
            }
        case .codex:
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Codex model"))
            let auto = ClosureMenuItem("Automatic — fastest (\(AISettings.autoCodexModel ?? "CLI default"))") { codexModel = "" }
            auto.state = codexModel.isEmpty ? .on : .off
            menu.addItem(auto)
            for m in AISettings.codexModels() {
                let item = ClosureMenuItem(m.name) { codexModel = m.slug }
                item.state = codexModel == m.slug ? .on : .off
                menu.addItem(item)
            }
        case .off:
            break
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("AI Settings…") {
            settingsTab = "ai"
            openSettings()
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
