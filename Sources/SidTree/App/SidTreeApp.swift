import AppKit
import SwiftUI

extension Notification.Name {
    static let openRepositoryRequest = Notification.Name("SidTreeOpenRepositoryRequest")
    static let openSettingsRequest = Notification.Name("SidTreeOpenSettingsRequest")
}

/// Repositories handed to the app from Finder, `open -a SidTree <dir>` or the command line.
enum LaunchRequests {
    static var pending: [URL] = []

    static func take() -> URL? {
        pending.isEmpty ? nil : pending.removeFirst()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        var isDir: ObjCBool = false
        for arg in CommandLine.arguments.dropFirst() where !arg.hasPrefix("-") {
            let url = URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                LaunchRequests.pending.append(url)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            Self.openRepository(url.standardizedFileURL.resolvingSymlinksInPath())
        }
    }

    /// When launched with paths, SwiftUI skips its default window; open one so the request is handled.
    private static var windowRequestScheduled = false

    static func ensureWindowForPendingRequests() {
        guard !windowRequestScheduled else { return }
        windowRequestScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            windowRequestScheduled = false
            guard !LaunchRequests.pending.isEmpty else { return }
            openNewWindow()
        }
    }

    /// Opens a new (start screen) window through File → New Window.
    static func openNewWindow() {
        if let fileMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.items.contains { $0.title == "New Window" } == true })?.submenu,
           let index = fileMenu.items.firstIndex(where: { $0.title == "New Window" }) {
            fileMenu.performActionForItem(at: index)
        }
    }

    private var terminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        return .terminateNow
    }

    /// Closing the last repository window shows the start screen instead of leaving no window at all.
    private func showStartScreenAfterLastRepositoryCloses() {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, !self.terminating,
                  let closing = note.object as? NSWindow,
                  closing.identifier?.rawValue.hasPrefix("repo-") == true,
                  closing.title != "SidTree"          // the start screen itself may close normally
            else { return }
            DispatchQueue.main.async {
                guard !self.terminating else { return }
                let stillOpen = NSApp.windows.contains {
                    $0 !== closing && $0.isVisible && $0.identifier?.rawValue.hasPrefix("repo-") == true
                }
                if !stillOpen { Self.openNewWindow() }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false   // repositories open as SidTree tabs
        AppearanceController.shared.apply()
        showStartScreenAfterLastRepositoryCloses()
        DebugSnapshot.scheduleIfRequested()
        if !LaunchRequests.pending.isEmpty { Self.ensureWindowForPendingRequests() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Right-click on the Dock icon: recent repositories, like Finder's recent folders.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for url in RecentRepos.shared.urls.prefix(12) {
            let item = ClosureMenuItem(url.lastPathComponent) { Self.openRepository(url) }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            item.toolTip = DisplayPath.of(url)
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem("Open Repository…") {
            NSApp.activate(ignoringOtherApps: true)
            if let url = RepoPicker.choose() { Self.openRepository(url) }
        })
        return menu
    }

    /// Switches to the repository's tab if it is open, otherwise opens it as a tab in the frontmost window.
    @MainActor
    static func openRepository(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        if Workspace.focus(url) { return }
        if let workspace = Workspace.target {
            workspace.bringToFront()
            workspace.open(url)
            return
        }
        if !LaunchRequests.pending.contains(url) { LaunchRequests.pending.append(url) }
        NotificationCenter.default.post(name: .openRepositoryRequest, object: nil)
        ensureWindowForPendingRequests()
    }
}

@main
struct SidTreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        DefaultsMigration.run()
    }

    var body: some Scene {
        WindowGroup("SidTree", id: "repo", for: URL.self) { $url in
            RepoWindow(url: $url)
                .handlesExternalEvents(preferring: Set([url?.absoluteString].compactMap { $0 }), allowing: ["*"])
                .onOpenURL { AppDelegate.openRepository($0) }
        }
        .defaultSize(width: 1400, height: 880)
        .windowStyle(.hiddenTitleBar)
        .commands { AppCommands() }

        Settings {
            SettingsView()
        }

        Window("What's New in SidTree", id: "whats-new") {
            WhatsNewView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Software Update", id: "update") {
            UpdateView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Focused values

struct FocusedRepoKey: FocusedValueKey { typealias Value = RepoModel }
struct FocusedWorkspaceKey: FocusedValueKey { typealias Value = Workspace }

extension FocusedValues {
    var repoModel: RepoModel? {
        get { self[FocusedRepoKey.self] }
        set { self[FocusedRepoKey.self] = newValue }
    }
    var workspace: Workspace? {
        get { self[FocusedWorkspaceKey.self] }
        set { self[FocusedWorkspaceKey.self] = newValue }
    }
}

/// Carries settings and recent repositories over from the app's previous name (GitSid).
enum DefaultsMigration {
    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromGitSid") else { return }
        d.set(true, forKey: "migratedFromGitSid")
        guard let old = d.persistentDomain(forName: "nl.sidworks.gitsid") else { return }
        for (key, value) in old where d.object(forKey: key) == nil && !key.hasPrefix("NSWindow") {
            d.set(value, forKey: key)
        }
    }
}
