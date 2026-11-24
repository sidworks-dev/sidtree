import SwiftUI

struct HistoryView: View {
    @Bindable var model: RepoModel
    @AppStorage("split.history") private var historySplit = 0.58
    @AppStorage("split.detail") private var detailSplit = 0.36
    @AppStorage("split.files") private var filesSplit = 0.45

    var body: some View {
        VStack(spacing: 12) {
            filterBar
            SplitPane(axis: .vertical, fraction: $historySplit, minFirst: 140, minSecond: 180) {
                Card {
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
            } second: {
                CommitDetailPanel(model: model, filesSplit: $filesSplit, detailSplit: $detailSplit)
            }
        }
        .padding(16)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            PillTabs(options: HistoryScope.allCases.map { ($0, $0.rawValue) }, selection: $model.historyScope)
            PillTabs(options: HistoryOrder.allCases.map { ($0, $0.rawValue) }, selection: $model.historyOrder)
            Toggle(isOn: $model.showRemotes) {
                Text("Remote branches").font(.system(size: 12))
            }
            .toggleStyle(.checkbox)
            .disabled(model.historyScope == .current)
            Spacer()
            if model.historyLoading { ProgressView().controlSize(.small) }
            Text("\(model.commitCount) commits")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
            SearchField(placeholder: "Search message, author, hash", text: $model.historySearch, width: 260)
        }
    }
}

/// Files + commit info + diff for the selected commit.
struct CommitDetailPanel: View {
    @Bindable var model: RepoModel
    @Binding var filesSplit: Double
    @Binding var detailSplit: Double
    @State private var fileSelection: Set<String> = []

    var body: some View {
        SplitPane(axis: .horizontal, fraction: $detailSplit, minFirst: 260, minSecond: 320) {
            SplitPane(axis: .vertical, fraction: $filesSplit, minFirst: 70, minSecond: 90) {
                Card {
                    VStack(spacing: 0) {
                        CardHeader(title: "Files", subtitle: model.commitDetail.map { "\($0.files.count)" })
                        if let detail = model.commitDetail {
                            FileListView(files: detail.files, focused: model.selectedCommitFile, selection: $fileSelection,
                                         onSelect: { model.selectCommitFile($0) },
                                         onDoubleClick: { file in
                                             if detail.hash == workingCopyID { model.open(file) }
                                         }) { file in
                                Button("Copy Path") { model.copyToPasteboard(file.path) }
                                Button("Show in Finder") { model.reveal(file) }
                                Button("Open") { model.open(file) }
                            }
                        } else {
                            empty("Select a commit")
                        }
                    }
                }
            } second: {
                Card {
                    if let detail = model.commitDetail {
                        CommitInfoView(model: model, detail: detail)
                    } else {
                        empty("No commit selected")
                    }
                }
            }
        } second: {
            DiffView(file: model.selectedCommitFile, diff: model.commitDiff,
                     context: model.commitDetail?.hash == workingCopyID ? .readOnly : .commit,
                     onHunk: { action, hunk in
                         if let diff = model.commitDiff { model.hunkAction(action, hunk: hunk, in: diff) }
                     })
        }
        .onChange(of: model.selectedCommitFile?.id) { _, id in
            if let id, !fileSelection.contains(id) { fileSelection = [id] }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CommitInfoView: View {
    let model: RepoModel
    let detail: CommitDetail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if detail.hash == workingCopyID {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil.and.outline").font(.system(size: 16)).foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34).background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uncommitted changes").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("\(detail.files.count) changed files in your working copy").font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Button("Open File Status") { model.sidebarSelection = .fileStatus }.buttonStyle(PillButtonStyle(prominent: true))
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        AvatarView(name: detail.author, size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.subject)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                            if !detail.body.isEmpty {
                                Text(detail.body)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    Rectangle().fill(Theme.border).frame(height: 1)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                        GridRow {
                            label("Commit")
                            HStack(spacing: 6) {
                                Text(detail.hash).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.text)
                                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                                Button { model.copyToPasteboard(detail.hash) } label: { Image(systemName: "doc.on.doc").font(.system(size: 10.5)) }
                                    .buttonStyle(.plain).foregroundStyle(Theme.secondaryText).help("Copy SHA")
                            }
                        }
                        GridRow {
                            label("Parents")
                            HStack(spacing: 8) {
                                ForEach(detail.parents, id: \.self) { p in
                                    Button(String(p.prefix(8))) { model.jump(to: p) }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(Theme.accent)
                                }
                                if detail.parents.isEmpty { Text("none").font(.system(size: 12)).foregroundStyle(Theme.secondaryText) }
                            }
                        }
                        GridRow {
                            label("Author")
                            Text("\(detail.author) <\(detail.authorEmail)>").font(.system(size: 12)).foregroundStyle(Theme.text).textSelection(.enabled)
                        }
                        if detail.committer != detail.author {
                            GridRow {
                                label("Committer")
                                Text(detail.committer).font(.system(size: 12)).foregroundStyle(Theme.text)
                            }
                        }
                        GridRow {
                            label("Date")
                            Text(Formatters.full.string(from: detail.authorDate)).font(.system(size: 12)).foregroundStyle(Theme.text)
                        }
                        if let i = model.rowIndex[detail.hash], case let refs = model.rows[i].commit.refs, !refs.isEmpty {
                            GridRow {
                                label("Labels")
                                Text(refs.map(\.name).joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.text)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).gridColumnAlignment(.trailing)
    }
}

struct StashDetailView: View {
    @Bindable var model: RepoModel
    @AppStorage("split.detail") private var detailSplit = 0.36
    @AppStorage("split.files") private var filesSplit = 0.45

    private var stash: Stash? {
        if case .stash(let ref) = model.sidebarSelection { return model.stashes.first { $0.ref == ref } }
        return nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if let stash {
                HStack(spacing: 10) {
                    Image(systemName: "tray.full").foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30).background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stash.message).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("\(stash.ref) · \(Formatters.relativeDate(stash.date))").font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("Delete") { model.dropStash(stash) }.buttonStyle(PillButtonStyle(destructive: true))
                    Button("Pop") { model.applyStash(stash, pop: true) }.buttonStyle(PillButtonStyle())
                    Button("Apply Stash") { model.applyStash(stash, pop: false) }.buttonStyle(PillButtonStyle(prominent: true))
                }
                CommitDetailPanel(model: model, filesSplit: $filesSplit, detailSplit: $detailSplit)
            } else {
                Text("Stash not found").foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }
}
