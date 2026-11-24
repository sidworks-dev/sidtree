import AppKit
import SwiftUI

struct RepoWindow: View {
    @Binding var url: URL?
    @State private var model: RepoModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                RepoView(model: model) { newURL in url = newURL }
                    .id(ObjectIdentifier(model))
            } else if url == nil {
                WelcomeView { url = $0 }
            } else {
                ProgressView().controlSize(.small)
                    .frame(minWidth: 1000, minHeight: 620)
                    .background(Theme.canvas)
            }
        }
        .focusedSceneValue(\.repoURL, $url)
        .task(id: url) { await load() }
        .onAppear {
            takeLaunchRequest()
            LaunchTasks.run(openWindow: openWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRepositoryRequest)) { _ in takeLaunchRequest() }
        .alert("Not a Git repository", isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    @Environment(\.openWindow) private var openWindow

    private func takeLaunchRequest() {
        guard url == nil, model == nil, let next = LaunchRequests.take() else { return }
        url = next
        while let more = LaunchRequests.take() { openWindow(id: "repo", value: more) }
    }

    private func load() async {
        guard let url else {
            model?.stop()
            model = nil
            return
        }
        if let model, model.root.standardizedFileURL == url.standardizedFileURL { return }
        guard let found = await GitService.resolveRoot(of: url) else {
            RecentRepos.shared.remove(url)
            loadError = "“\(url.path)” is not inside a Git repository."
            self.url = nil
            return
        }
        if found.root.standardizedFileURL != url.standardizedFileURL {
            self.url = found.root   // normalise to the top level; triggers a reload
            return
        }
        model?.stop()
        let m = RepoModel(root: found.root, gitDir: found.gitDir)
        model = m
        m.start()
        RecentRepos.shared.add(found.root)
    }
}

struct RepoView: View {
    @Bindable var model: RepoModel
    let switchRepo: (URL?) -> Void
    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 280

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model, switchRepo: switchRepo)
                .frame(width: sidebarWidth)
                .background(Theme.sidebar)
            SidebarResizeHandle(width: $sidebarWidth)
            VStack(spacing: 0) {
                TopBar(model: model)
                Rectangle().fill(Theme.border).frame(height: 1)
                Group {
                    switch model.sidebarSelection {
                    case .fileStatus:
                        FileStatusView(model: model)
                    case .stash:
                        StashDetailView(model: model)
                    default:
                        HistoryView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.canvas)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1000, minHeight: 620)
        .tint(Theme.accent)
        .navigationTitle(model.name)
        .focusedSceneValue(\.repoModel, model)
        .sheet(item: $model.sheet) { kind in
            SheetHost(model: model, kind: kind)
        }
        .alert(item: $model.error) { err in
            Alert(title: Text("Git error"), message: Text(err.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog(model.confirm?.title ?? "", isPresented: Binding(get: { model.confirm != nil }, set: { if !$0 { model.confirm = nil } }),
                            presenting: model.confirm) { req in
            Button(req.actionTitle, role: req.destructive ? .destructive : nil) { req.action() }
            Button("Cancel", role: .cancel) {}
        } message: { req in
            Text(req.message)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
    }
}

struct TopBar: View {
    let model: RepoModel

    private var title: String {
        switch model.sidebarSelection {
        case .fileStatus: return "File Status"
        case .stash: return "Stash"
        default: return "History"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9.5, weight: .semibold))
                    Text(branchText).lineLimit(1)
                    if let up = model.status.upstream {
                        Text("→ \(up)").foregroundStyle(Theme.secondaryText.opacity(0.8)).lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
            .allowsHitTesting(false)

            if let activity = model.activity {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(activity).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Theme.violetSoft, in: Capsule())
                .transition(.opacity)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button { model.requestCommit() } label: {
                    Label("Commit", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .help("Commit staged changes (⇧⌘C)")

                ActionButton(title: "Pull", symbol: "arrow.down", badge: model.status.behind) { model.sheet = .pull }
                    .help("Pull (⇧⌘L)")
                ActionButton(title: "Push", symbol: "arrow.up", badge: model.status.ahead) { model.sheet = .push }
                    .help("Push (⇧⌘P)")
                ActionButton(title: "Fetch", symbol: "arrow.triangle.2.circlepath", badge: 0) { model.fetch() }
                    .help("Fetch all remotes (⇧⌘F)")
            }

            Rectangle().fill(Theme.border).frame(width: 1, height: 22)

            HStack(spacing: 6) {
                ActionButton(title: "Branch", symbol: "arrow.triangle.branch", badge: 0) { model.sheet = .newBranch(startPoint: nil) }
                    .help("New branch (⇧⌘B)")
                ActionButton(title: "Merge", symbol: "arrow.triangle.merge", badge: 0) { model.sheet = .merge(nil) }
                    .help("Merge into current branch (⇧⌘M)")
                ActionButton(title: "Stash", symbol: "tray.and.arrow.down", badge: 0) { model.sheet = .stash }
                    .disabled(!model.hasLocalChanges)
                    .help("Stash local changes (⇧⌘S)")
            }

            Rectangle().fill(Theme.border).frame(width: 1, height: 22)

            HStack(spacing: 6) {
                IconButton(symbol: "globe", help: "Open remote in browser") { model.openRemoteInBrowser() }
                    .disabled(model.remotes.isEmpty)
                IconButton(symbol: "folder", help: "Show in Finder") { model.showInFinder() }
                IconButton(symbol: "terminal", help: "Open in Terminal (⌥⌘T)") { model.openTerminal() }
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .frame(height: 64)
        .background(WindowDragArea())
        .background(Theme.canvas)
        .animation(.easeInOut(duration: 0.15), value: model.activity)
    }

    private var branchText: String {
        if let b = model.currentBranch { return b }
        if let h = model.status.headOID { return "detached at \(h.prefix(8))" }
        return "no commits yet"
    }
}

struct ActionButton: View {
    let title: String
    let symbol: String
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title)
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 16)
                        .background(Capsule().fill(Theme.accent))
                }
            }
        }
        .buttonStyle(PillButtonStyle())
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 14)
        }
        .buttonStyle(PillButtonStyle())
        .help(help)
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text(text).foregroundStyle(Theme.text)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

/// 1pt divider with a wider invisible grab area to resize the sidebar.
struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if start == nil { start = width }
                                width = min(max((start ?? width) + value.translation.width, 200), 520)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .zIndex(1)
    }
}
