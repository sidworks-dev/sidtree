import AppKit
import SwiftUI

struct RepoWindow: View {
    @Binding var url: URL?
    @State private var workspace = Workspace()
    @State private var positioner: TrafficLightPositioner?
    @State private var restored = false
    @SceneStorage("workspace.tabs") private var savedTabs = ""
    @SceneStorage("workspace.active") private var savedActive = ""
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace)
            Group {
                if let tab = workspace.active {
                    RepoView(model: tab.model)
                        .id(tab.id)
                } else {
                    RepositoriesView { workspace.open($0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1100, minHeight: 640)
        .tint(Theme.accent)
        .navigationTitle(workspace.activeModel?.name ?? "SidTree")
        .background(WindowAccessor { window in
            workspace.attach(window)
            if positioner == nil { positioner = TrafficLightPositioner(window: window) }
            positioner?.apply()
        })
        .focusedSceneValue(\.workspace, workspace)
        .onAppear {
            restore()
            LaunchTasks.run(openWindow: openWindow)
        }
        .onChange(of: url) { _, _ in takeURL() }
        .onChange(of: workspace.tabPaths) { _, paths in
            guard restored else { return }
            savedTabs = paths.joined(separator: "\n")
        }
        .onChange(of: workspace.activeID) { _, _ in
            guard restored else { return }
            savedActive = workspace.activeModel?.root.path ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRepositoryRequest)) { _ in takeLaunchRequests() }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { note in
            if workspace.window?.isKeyWindow == true || (note.object as? String == "debug" && Workspace.target === workspace) {
                openSettings()
            }
        }
        .onDisappear { workspace.stopAll() }
        .alert("Not a Git repository", isPresented: errorShown) {
            Button("OK") { workspace.loadError = nil }
        } message: {
            Text(workspace.loadError ?? "")
        }
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { workspace.loadError != nil }, set: { if !$0 { workspace.loadError = nil } })
    }

    /// Reopens the tabs this window had, then whatever the window was opened for.
    private func restore() {
        guard !restored else { return }
        let paths = savedTabs.split(separator: "\n").map(String.init).filter { FileManager.default.fileExists(atPath: $0) }
        let active = savedActive
        var urls = paths.map { URL(fileURLWithPath: $0) }
        if let url { urls.append(url) }
        while let next = LaunchRequests.take() { urls.append(next) }
        let focus = url?.path ?? (urls.count > paths.count ? urls.last?.path : nil) ?? (active.isEmpty ? nil : active)
        url = nil
        Task {
            for u in urls { await workspace.openNow(u, activate: false) }
            if let focus, let tab = workspace.tabs.first(where: { $0.root.path == focus }) ?? workspace.tab(for: URL(fileURLWithPath: focus)) {
                workspace.activate(tab.id)
            } else if !active.isEmpty || urls.isEmpty {
                // nothing to focus: stay on the overview
            } else {
                workspace.activeID = workspace.tabs.last?.id
            }
            if ProcessInfo.processInfo.environment["SIDTREE_DEBUG_OVERVIEW"] != nil { workspace.showOverview() }
            restored = true
            savedTabs = workspace.tabPaths.joined(separator: "\n")
            savedActive = workspace.activeModel?.root.path ?? ""
        }
    }

    private func takeURL() {
        guard let next = url else { return }
        url = nil
        workspace.open(next)
    }

    private func takeLaunchRequests() {
        guard Workspace.target == nil || Workspace.target === workspace else { return }
        while let next = LaunchRequests.take() { workspace.open(next) }
    }
}

struct RepoView: View {
    @Bindable var model: RepoModel
    @AppStorage("sidebarWidth.v2") private var sidebarWidth: Double = 224

    var body: some View {
        VStack(spacing: 0) {
            RepoToolbar(model: model)
            HStack(spacing: 0) {
                SidebarView(model: model)
                    .frame(width: sidebarWidth)
                    .background(Theme.sidebar)
                ColumnResizeHandle(width: $sidebarWidth, range: 190...420)
                Group {
                    switch model.sidebarSelection {
                    case .changes:
                        ChangesView(model: model)
                    case .stash:
                        StashDetailView(model: model)
                    default:
                        HistoryView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas)
            }
        }
        .focusedSceneValue(\.repoModel, model)
        .sheet(item: $model.sheet) { kind in
            SheetHost(model: model, kind: kind)
        }
        .sheet(item: $model.problem) { report in
            ProblemView(report: report)
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

/// 1pt divider with a wider invisible grab area to resize the column on its left.
struct ColumnResizeHandle: View {
    @Binding var width: Double
    var range: ClosedRange<Double> = 190...520
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
                                width = min(max((start ?? width) + value.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .zIndex(1)
    }
}
