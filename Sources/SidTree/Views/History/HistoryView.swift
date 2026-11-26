import SwiftUI

struct HistoryView: View {
    @Bindable var model: RepoModel
    @AppStorage("split.history.v2") private var historySplit = 0.6

    var body: some View {
        // Without a selected commit the list takes the whole width; the details appear once you pick one.
        SplitPane(axis: .horizontal, fraction: $historySplit, minFirst: 520, minSecond: 360, divider: true,
                  hideSecond: model.selectedCommitID == nil) {
            VStack(spacing: 0) {
                filterBar
                HistoryTable(model: model,
                             version: model.historyVersion,
                             selectedID: model.selectedCommitID,
                             scrollToken: model.scrollRequest?.token ?? 0,
                             filtering: model.isFilteringHistory)
                    .overlay {
                        if model.displayRows.isEmpty && !model.historyLoading {
                            Text(model.isFilteringHistory ? "No commits match “\(model.historySearch)”" : "No commits yet")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        }
                    }
            }
            .background(Theme.canvas)
        } second: {
            CommitDetailPanel(model: model)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Text("History")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .padding(.trailing, 6)
            PillTabs(options: [(HistoryScope.all, "All branches"), (HistoryScope.current, "Current")], selection: $model.historyScope)
            Menu {
                Picker("Order", selection: $model.historyOrder) {
                    ForEach(HistoryOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Show Remote Branches", isOn: $model.showRemotes)
                    .disabled(model.historyScope == .current)
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .handCursor()
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Commit order and remote branches")
            Spacer(minLength: 8)
            if model.historyLoading { ProgressView().controlSize(.small) }
            Text(model.commitCount == 1 ? "1 commit" : "\(model.commitCount) commits")
                .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .fixedSize()
            SearchField(placeholder: "Message, author, hash", text: $model.historySearch, width: 220)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// Header, files and diff of the selected commit.
struct CommitDetailPanel: View {
    @Bindable var model: RepoModel
    @State private var fileSelection: Set<String> = []
    /// Most of the panel height the file list may take; it shrinks to fit fewer files.
    /// Drag the line between files and code to change it.
    @AppStorage("split.detail.files.v2") private var filesSplit = 0.45

    var body: some View {
        VStack(spacing: 0) {
            if let detail = model.commitDetail {
                if detail.hash == workingCopyID {
                    WorkingCopyHeader(model: model, count: detail.files.count)
                } else {
                    CommitHeader(model: model, detail: detail)
                }
                let listHeight = CGFloat(detail.files.count) * FileListMetrics.rowHeight + FileListMetrics.padding * 2 + 2
                SplitPane(axis: .vertical, fraction: $filesSplit, minFirst: min(listHeight, 76), minSecond: 120,
                          maxFirst: listHeight, divider: true) {
                    files(detail)
                } second: {
                    DiffView(file: model.selectedCommitFile, diff: model.commitDiff,
                             context: detail.hash == workingCopyID ? .readOnly : .commit,
                             style: .flat, showsHeader: false,
                             onHunk: { action, hunk in
                                 if let diff = model.commitDiff { model.hunkAction(action, hunk: hunk, in: diff) }
                             },
                             openLine: model.selectedCommitFile.flatMap { file in
                                 file.kind == .deleted ? nil : { model.openInEditor(path: file.path, line: $0) }
                             },
                             editorName: model.editorName)
                }
            } else {
                Text("Select a commit to see its changes")
                    .font(.system(size: 13)).foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.column)
        .onChange(of: model.selectedCommitFile?.id) { _, id in
            if let id, !fileSelection.contains(id) { fileSelection = [id] }
        }
    }

    private func files(_ detail: CommitDetail) -> some View {
        let stats = model.commitStats?.hash == detail.hash ? model.commitStats?.stats : nil
        return FileListView(files: detail.files, selection: $fileSelection,
                            onSelect: { model.selectCommitFile($0) },
                            onDoubleClick: { file in
                                if detail.hash == workingCopyID { model.open(file) }
                            },
                            detail: { file in stats?[file.path].map(Self.statText) },
                            selectionFill: Theme.controlHover) { file in
            Button("Open") { model.open(file) }
            Button("Open in \(model.editorName)") { model.openInEditor([file]) }
            Button("Show in Finder") { model.reveal(file) }
            Divider()
            Button("Copy Path") { model.copyToPasteboard(file.path) }
        }
        .padding(.horizontal, 2)
    }

    static func statText(_ stat: LineStat) -> String {
        guard let added = stat.added, let removed = stat.removed else { return "binary" }
        return [added > 0 ? "+\(added)" : nil, removed > 0 ? "−\(removed)" : nil].compactMap { $0 }.joined(separator: " ")
    }
}

private struct CommitHeader: View {
    let model: RepoModel
    let detail: CommitDetail
    @State private var copied = false

    private var totals: (added: Int, removed: Int)? {
        guard let stats = model.commitStats, stats.hash == detail.hash else { return nil }
        return stats.stats.values.reduce(into: (0, 0)) { sum, s in
            sum.0 += s.added ?? 0
            sum.1 += s.removed ?? 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(name: detail.author, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(detail.subject)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text("\(detail.author) · \(Formatters.historyDate(detail.authorDate))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .help("\(detail.author) <\(detail.authorEmail)> · \(Formatters.full.string(from: detail.authorDate))"
                              + (detail.committer != detail.author ? "\nCommitted by \(detail.committer)" : ""))
                }
                Spacer(minLength: 8)
                Button {
                    model.copyToPasteboard(detail.hash)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        copied = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(String(detail.hash.prefix(8)))
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.softText)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.fieldBorder, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .handCursor()
                .help("Copy commit SHA \(detail.hash)")
            }
            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Text(detail.parents.count > 1 ? "Parents" : "Parent")
                    if detail.parents.isEmpty { Text("none") }
                    ForEach(detail.parents, id: \.self) { p in
                        Button(String(p.prefix(8))) { model.jump(to: p) }
                            .buttonStyle(.plain)
                            .handCursor()
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .help("Go to parent \(p.prefix(8))")
                    }
                }
                HStack(spacing: 4) {
                    Text(detail.files.count == 1 ? "1 file" : "\(detail.files.count) files")
                    if let totals, totals.added + totals.removed > 0 {
                        Text("·")
                        if totals.added > 0 { Text("+\(totals.added)").foregroundStyle(Theme.addedText) }
                        if totals.removed > 0 { Text("−\(totals.removed)").foregroundStyle(Theme.removedText) }
                    }
                }
                if let i = model.rowIndex[detail.hash], case let refs = model.rows[i].commit.refs.filter({ $0.kind == .tag }), !refs.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "tag").font(.system(size: 10))
                        Text(refs.map(\.name).joined(separator: ", ")).lineLimit(1)
                    }
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.tertiaryText)
            if !detail.body.isEmpty {
                ScrollView {
                    Text(detail.body)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

private struct WorkingCopyHeader: View {
    let model: RepoModel
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.square").font(.system(size: 15)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30).background(Circle().fill(Theme.avatarFill))
            VStack(alignment: .leading, spacing: 1) {
                Text("Uncommitted changes").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Text(count == 1 ? "1 changed file in your working copy" : "\(count) changed files in your working copy")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Button("Open Changes") { model.sidebarSelection = .changes }
                .buttonStyle(PillButtonStyle(prominent: true, compact: true))
        }
        .padding(16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

struct StashDetailView: View {
    @Bindable var model: RepoModel
    @AppStorage("split.history.v2") private var historySplit = 0.6

    private var stash: Stash? {
        if case .stash(let ref) = model.sidebarSelection { return model.stashes.first { $0.ref == ref } }
        return nil
    }

    var body: some View {
        if let stash {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox").font(.system(size: 14)).foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30).background(Circle().fill(Theme.avatarFill))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stash.message).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("\(stash.ref) · \(Formatters.historyDate(stash.date))").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("Delete") { model.dropStash(stash) }.buttonStyle(PillButtonStyle(destructive: true))
                    Button("Pop") { model.applyStash(stash, pop: true) }.buttonStyle(PillButtonStyle())
                    Button("Apply Stash") { model.applyStash(stash, pop: false) }.buttonStyle(PillButtonStyle(prominent: true))
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
                CommitDetailPanel(model: model)
            }
        } else {
            Text("Stash not found").foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
