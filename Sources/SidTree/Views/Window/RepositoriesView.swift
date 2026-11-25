import AppKit
import Observation
import SwiftUI

struct RepoSummary {
    var branch: String?
    var ahead = 0
    var behind = 0
    var changes = 0
    var lastSubject = ""
    var lastDate: Date?
    var missing = false
}

@MainActor
@Observable
final class RepositoriesModel {
    /// Shared so the overview shows the last known state at once and refreshes in the background.
    static let shared = RepositoriesModel()
    var summaries: [URL: RepoSummary] = [:]
    var loading = false

    func load(_ urls: [URL]) async {
        loading = true
        await withTaskGroup(of: (URL, RepoSummary).self) { group in
            for url in urls {
                group.addTask { (url, await Self.summary(for: url)) }
            }
            for await (url, summary) in group {
                summaries[url] = summary
            }
        }
        loading = false
    }

    nonisolated static func summary(for url: URL) async -> RepoSummary {
        guard FileManager.default.fileExists(atPath: url.path) else { return RepoSummary(missing: true) }
        async let statusResult = GitRunner.run(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=normal"], in: url)
        async let logResult = GitRunner.run(["log", "-1", "--format=%s%x1f%at"], in: url)
        let (st, lg) = await (statusResult, logResult)
        let snap = Parsers.parseStatus(st.stdout)
        var s = RepoSummary()
        s.branch = snap.branch ?? snap.headOID.map { "detached \($0.prefix(7))" }
        s.ahead = snap.ahead
        s.behind = snap.behind
        s.changes = Set(snap.staged.map(\.path) + snap.unstaged.map(\.path)).count
        let parts = lg.output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\u{1F}", maxSplits: 1)
        if parts.count == 2 {
            s.lastSubject = String(parts[0])
            s.lastDate = Date(timeIntervalSince1970: TimeInterval(parts[1]) ?? 0)
        }
        return s
    }
}

/// Repositories overview: shown in a window without an active tab.
struct RepositoriesView: View {
    let open: (URL) -> Void
    @ObservedObject private var recent = RecentRepos.shared
    @State private var model = RepositoriesModel.shared
    @State private var query = ""
    @State private var showClone = false

    private var filtered: [URL] {
        query.isEmpty ? recent.urls : recent.urls.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 18)
                list
                Text("⌘O open · ⌘T new tab · ⌘N new window")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .task(id: recent.urls) { await model.load(recent.urls) }
        .sheet(isPresented: $showClone) {
            CloneSheet(defaultParent: ProjectFolder.url ?? recent.urls.first?.deletingLastPathComponent()) { open($0) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Repositories").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
            summary
                .font(.system(size: 13))
                .lineLimit(1)
            if model.loading { ProgressView().controlSize(.small) }
            Spacer(minLength: 12)
            SearchField(placeholder: "Filter repositories", text: $query, width: 260, height: 30)
            Button("Clone") { showClone = true }
                .buttonStyle(PillButtonStyle())
            Button("Open Repository") { pick() }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut("o")
        }
    }

    private var summary: Text {
        let s = recent.urls.compactMap { model.summaries[$0] }
        let changed = s.filter { $0.changes > 0 }.count
        let ahead = s.reduce(0) { $0 + $1.ahead }
        let behind = s.reduce(0) { $0 + $1.behind }
        let count = recent.urls.count
        var text = Text(count == 1 ? "1 repository" : "\(count) repositories").foregroundColor(Theme.secondaryText)
        if changed > 0 {
            text = text + Text(" · ").foregroundColor(Theme.secondaryText)
                + Text("\(changed) with local changes").foregroundColor(Theme.orange)
        }
        var sync: [String] = []
        if ahead > 0 { sync.append("\(ahead) to push") }
        if behind > 0 { sync.append("\(behind) to pull") }
        let syncText = sync.isEmpty ? "nothing to push or pull" : sync.joined(separator: ", ")
        return text + Text(" · \(syncText)").foregroundColor(Theme.secondaryText)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            VStack(spacing: 10) {
                Text(recent.urls.isEmpty ? "Open or clone a repository to get started" : "No repositories match “\(query)”")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                if recent.urls.isEmpty {
                    Button("Open Repository") { pick() }.buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element) { index, url in
                    RepoRow(url: url, summary: model.summaries[url], last: index == filtered.count - 1) { open(url) }
                        .contextMenu {
                            Button("Open") { open(url) }
                            Button("Open in \(EditorSettings.current?.name ?? "Editor")") { EditorSettings.open([url]) }
                                .disabled(EditorSettings.current == nil)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button("Remove from List") { recent.remove(url) }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
    }

    private func pick() {
        if let url = RepoPicker.choose() { open(url) }
    }
}

private struct RepoRow: View {
    let url: URL
    let summary: RepoSummary?
    let last: Bool
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Text(String(url.lastPathComponent.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.tileFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(DisplayPath.parent(of: url))
                        .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).lineLimit(1).truncationMode(.middle)
                }
                .frame(minWidth: 160, maxWidth: 420, alignment: .leading)
                .layoutPriority(1)
                if let s = summary {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 10, weight: .medium))
                        Text(s.branch ?? "—").lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.softText)
                    .frame(width: 140, alignment: .leading)
                    status(s)
                        .frame(width: 110, alignment: .leading)
                    Text(s.missing ? "Folder not found" : (s.lastSubject.isEmpty ? "No commits yet" : s.lastSubject))
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if let d = s.lastDate {
                            Text(d, format: .relative(presentation: .named))
                        } else {
                            Text("")
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                    .frame(width: 100, alignment: .trailing)
                } else {
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(hover ? Color(nsColor: Theme.dynamic(0xF5F3EF, 0x3A3835)) : .clear)
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Color(nsColor: Theme.dynamic(0xEFECE6, 0x403D3A))).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
        .help(url.path)
    }

    private func status(_ s: RepoSummary) -> some View {
        let (text, color): (String, Color) = {
            if s.missing { return ("Missing", Theme.red) }
            if s.changes > 0 { return ("\(s.changes) changed", Theme.orange) }
            if s.ahead > 0 || s.behind > 0 {
                let parts = [s.ahead > 0 ? "↑\(s.ahead)" : nil, s.behind > 0 ? "↓\(s.behind)" : nil].compactMap { $0 }
                return (parts.joined(separator: " "), Theme.accent)
            }
            return ("Clean", Theme.green)
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundStyle(color)
    }
}
