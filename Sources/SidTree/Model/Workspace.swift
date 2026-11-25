import AppKit
import Observation
import SwiftUI

/// One open repository in a window's tab strip.
@MainActor
final class RepoTab: Identifiable {
    let id = UUID()
    let model: RepoModel

    init(model: RepoModel) { self.model = model }

    var root: URL { model.root }
}

/// The repository tabs of one window. `activeID == nil` shows the repositories overview.
@MainActor
@Observable
final class Workspace {
    private(set) var tabs: [RepoTab] = []
    var activeID: UUID? {
        didSet { for tab in tabs { tab.model.isVisible = tab.id == activeID } }
    }
    var loadError: String?
    @ObservationIgnored private(set) weak var window: NSWindow?

    var active: RepoTab? { tabs.first { $0.id == activeID } }
    var activeModel: RepoModel? { active?.model }
    var tabPaths: [String] { tabs.map(\.root.path) }

    init() { Self.registry.append(WeakWorkspace(self)) }

    // MARK: Tabs

    /// Opens a repository in a new tab, or switches to the tab that already shows it.
    func open(_ url: URL) {
        Task { await openNow(url) }
    }

    /// Opens tabs in order, e.g. when restoring a window.
    func open(_ urls: [URL], activate path: String? = nil) {
        Task {
            for url in urls { await openNow(url, activate: false) }
            if let path, let tab = tabs.first(where: { $0.root.path == path }) {
                activeID = tab.id
            } else if activeID == nil {
                activeID = tabs.last?.id
            }
        }
    }

    @discardableResult
    func openNow(_ url: URL, activate: Bool = true) async -> Bool {
        if let tab = tab(for: url) {
            if activate { activeID = tab.id }
            return true
        }
        guard let found = await GitService.resolveRoot(of: url) else {
            RecentRepos.shared.remove(url)
            loadError = "“\(url.path)” is not inside a Git repository."
            return false
        }
        if let tab = tab(for: found.root) {
            if activate { activeID = tab.id }
            return true
        }
        // Already open in another window: bring that one forward instead of opening it twice.
        if activate, Self.focus(found.root) { return true }
        let model = RepoModel(root: found.root, gitDir: found.gitDir)
        let tab = RepoTab(model: model)
        tabs.append(tab)
        model.isVisible = false
        if activate || activeID == nil { activeID = tab.id }
        model.start()
        RecentRepos.shared.add(found.root)
        return true
    }

    func activate(_ id: UUID) { activeID = id }

    func showOverview() { activeID = nil }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        tab.model.stop()
        if activeID == id {
            activeID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    func closeOthers(_ id: UUID) {
        for tab in tabs where tab.id != id { close(tab.id) }
        activeID = id
    }

    func move(_ id: UUID, before target: UUID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
    }

    /// Next (+1) or previous (−1) tab, wrapping around through the overview.
    func cycle(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        let slots = tabs.count + 1        // the last slot is the overview
        let current = tabs.firstIndex { $0.id == activeID } ?? tabs.count
        let next = ((current + delta) % slots + slots) % slots
        activeID = next == tabs.count ? nil : tabs[next].id
    }

    func stopAll() {
        for tab in tabs { tab.model.stop() }
    }

    func tab(for url: URL) -> RepoTab? {
        let path = Self.canonical(url)
        return tabs.first { Self.canonical($0.root) == path }
    }

    // MARK: Window

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { Self.lastActive = WeakWorkspace(self) } }
        }
        if window.isKeyWindow { Self.lastActive = WeakWorkspace(self) }
    }

    func bringToFront() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Registry

    struct WeakWorkspace {
        weak var value: Workspace?
        init(_ value: Workspace) { self.value = value }
    }

    private static var registry: [WeakWorkspace] = []
    private static var lastActive: WeakWorkspace?

    private static var live: [Workspace] {
        registry.removeAll { $0.value == nil }
        return registry.compactMap(\.value).filter { $0.window?.isVisible == true || $0.window?.isMiniaturized == true }
    }

    /// The window new repositories open in: the most recently active one.
    static var target: Workspace? {
        if let last = lastActive?.value, live.contains(where: { $0 === last }) { return last }
        return live.first
    }

    /// Switches to the tab showing `url` in whichever window has it.
    @discardableResult
    static func focus(_ url: URL) -> Bool {
        for workspace in live {
            if let tab = workspace.tab(for: url) {
                workspace.activeID = tab.id
                workspace.bringToFront()
                return true
            }
        }
        return false
    }

    static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Hands the hosting NSWindow to the workspace.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
    }
}
