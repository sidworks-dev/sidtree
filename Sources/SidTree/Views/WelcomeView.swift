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
final class WelcomeModel {
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

struct WelcomeView: View {
    let open: (URL) -> Void
    @ObservedObject private var recent = RecentRepos.shared
    @State private var model = WelcomeModel()
    @State private var query = ""
    @State private var showClone = false

    private var filtered: [URL] {
        query.isEmpty ? recent.urls : recent.urls.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 252)
                .background(Theme.sidebar)
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        statCards
                        repoGrid
                    }
                    .padding(22)
                }
            }
            .background(Theme.canvas)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1000, minHeight: 620)
        .tint(Theme.accent)
        .navigationTitle("SidTree")
        .task(id: recent.urls) { await model.load(recent.urls) }
        .sheet(isPresented: $showClone) {
            CloneSheet(defaultParent: recent.urls.first?.deletingLastPathComponent()) { open($0) }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SidTree").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(AppInfo.version).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                UpdateBadge()
            }
            .padding(.horizontal, 16)
            .padding(.top, 38)
            .padding(.bottom, 12)
            .background(WindowDragArea())
            Rectangle().fill(Theme.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 2) {
                NavRow(symbol: "square.grid.2x2", title: "Repositories", badge: recent.urls.count, selected: true) {}
                NavRow(symbol: "folder.badge.plus", title: "Open Repository…", badge: 0, selected: false) { pick() }
                NavRow(symbol: "square.and.arrow.down", title: "Clone Repository…", badge: 0, selected: false) { showClone = true }

                if !recent.urls.isEmpty {
                    Text("RECENT")
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 5)
                    ForEach(recent.urls.prefix(8), id: \.self) { url in
                        ItemRow(symbol: "folder", title: url.lastPathComponent, selected: false) { open(url) } doubleTap: {}
                    }
                }
            }
            .padding(10)

            Spacer()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard").foregroundStyle(Theme.secondaryText)
                    Text("⌘O open · ⌘N new window").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Repositories").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Your recently opened projects at a glance").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            .allowsHitTesting(false)
            Spacer()
            SearchField(placeholder: "Search repositories", text: $query, width: 240)
            Button { showClone = true } label: { Label("Clone", systemImage: "square.and.arrow.down") }
                .buttonStyle(PillButtonStyle())
            Button { pick() } label: { Label("Open Repository", systemImage: "plus") }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut("o")
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .frame(height: 64)
        .background(WindowDragArea())
        .background(Theme.canvas)
    }

    // MARK: Stats

    private var statCards: some View {
        let s = Array(model.summaries.values)
        return HStack(spacing: 12) {
            StatCard(title: "Repositories", value: "\(recent.urls.count)", symbol: "folder", tint: Theme.accent, soft: Theme.violetSoft)
            StatCard(title: "With local changes", value: "\(s.filter { $0.changes > 0 }.count)", symbol: "pencil", tint: Theme.orange, soft: Theme.orangeSoft)
            StatCard(title: "Commits to push", value: "\(s.reduce(0) { $0 + $1.ahead })", symbol: "arrow.up", tint: Theme.green, soft: Theme.greenSoft)
            StatCard(title: "Commits to pull", value: "\(s.reduce(0) { $0 + $1.behind })", symbol: "arrow.down", tint: Theme.blue, soft: Theme.blueSoft)
        }
    }

    // MARK: Grid

    @ViewBuilder
    private var repoGrid: some View {
        HStack {
            Text("Recent repositories").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            if model.loading { ProgressView().controlSize(.small) }
            Spacer()
        }
        if filtered.isEmpty {
            Card {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.accent.opacity(0.7))
                    Text(recent.urls.isEmpty ? "Open or clone a repository to get started" : "No repositories match “\(query)”")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    if recent.urls.isEmpty {
                        Button { pick() } label: { Label("Open Repository", systemImage: "plus") }.buttonStyle(PillButtonStyle(prominent: true))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(filtered, id: \.self) { url in
                    RepoCard(url: url, summary: model.summaries[url]) { open(url) }
                        .contextMenu {
                            Button("Open") { open(url) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button("Remove from List") { recent.remove(url) }
                        }
                }
            }
        }
    }

    private func pick() {
        if let url = RepoPicker.choose() { open(url) }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    let soft: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint.opacity(0.8))
            }
            Text(value).font(.system(size: 26, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(LinearGradient(colors: [Theme.card, soft], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct RepoCard: View {
    let url: URL
    let summary: RepoSummary?
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(String(url.lastPathComponent.prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(hover ? Theme.accent : Theme.secondaryText.opacity(0.5))
                }

                if let s = summary {
                    if s.missing {
                        SoftBadge(text: "Folder not found", color: Theme.red, background: Theme.redSoft)
                    } else {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5, weight: .semibold))
                                Text(s.branch ?? "—").lineLimit(1).truncationMode(.middle)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.graySoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            if s.changes > 0 { SoftBadge(text: "\(s.changes) changed", color: Theme.orange, background: Theme.orangeSoft) }
                            if s.ahead > 0 { SoftBadge(text: "\(s.ahead)↑", color: Theme.green, background: Theme.greenSoft) }
                            if s.behind > 0 { SoftBadge(text: "\(s.behind)↓", color: Theme.blue, background: Theme.blueSoft) }
                            if s.changes == 0 && s.ahead == 0 && s.behind == 0 {
                                SoftBadge(text: "● Clean", color: Theme.green, background: Theme.greenSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        Rectangle().fill(Theme.border).frame(height: 1)
                        HStack(spacing: 6) {
                            Text(s.lastSubject.isEmpty ? "No commits yet" : s.lastSubject)
                                .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                            Spacer(minLength: 4)
                            if let d = s.lastDate {
                                Text(d, format: .relative(presentation: .named))
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondaryText.opacity(0.8)).lineLimit(1)
                            }
                        }
                    }
                } else {
                    HStack { ProgressView().controlSize(.small); Spacer() }.frame(height: 48)
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(hover ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(hover ? 0.08 : 0.02), radius: hover ? 8 : 2, y: hover ? 3 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - Clone

struct CloneSheet: View {
    let defaultParent: URL?
    let onCloned: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var remote = ""
    @State private var parent: URL?
    @State private var name = ""
    @State private var nameEdited = false
    @State private var running = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36).background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clone Repository").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Uses your SSH keys / keychain credentials").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(20)
            Rectangle().fill(Theme.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Source URL")
                    StyledTextField(placeholder: "git@bitbucket.org:team/project.git", text: $remote)
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Destination folder")
                    HStack {
                        Text((parent?.path as NSString?)?.abbreviatingWithTildeInPath ?? "Choose…")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { chooseParent() }.buttonStyle(PillButtonStyle(compact: true))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Name")
                    StyledTextField(placeholder: "project", text: Binding(get: { name }, set: { name = $0; nameEdited = true }))
                }
                if let error {
                    Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.red).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                if running {
                    ProgressView().controlSize(.small)
                    Text("Cloning…").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction).disabled(running)
                Button("Clone") { clone() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(running || remote.isEmpty || parent == nil || name.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.subtle)
        }
        .frame(width: 520)
        .background(Theme.card)
        .tint(Theme.accent)
        .onAppear { parent = defaultParent ?? FileManager.default.homeDirectoryForCurrentUser }
        .onChange(of: remote) { _, value in
            guard !nameEdited else { return }
            var n = value.trimmingCharacters(in: .whitespaces)
            if n.hasSuffix("/") { n.removeLast() }
            n = String(n.split(whereSeparator: { $0 == "/" || $0 == ":" }).last ?? "")
            if n.hasSuffix(".git") { n.removeLast(4) }
            name = n
        }
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK { parent = panel.url }
    }

    private func clone() {
        guard let parent else { return }
        running = true
        error = nil
        let dest = parent.appendingPathComponent(name)
        let src = remote.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await GitRunner.check(["clone", "--", src, dest.path], in: parent)
                running = false
                dismiss()
                onCloned(dest)
            } catch {
                running = false
                self.error = error.localizedDescription
            }
        }
    }
}
