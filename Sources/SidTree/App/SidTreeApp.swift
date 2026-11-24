import AppKit
import SwiftUI

extension Notification.Name {
    static let openRepositoryRequest = Notification.Name("SidTreeOpenRepositoryRequest")
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
        for url in urls where url.isFileURL && !LaunchRequests.pending.contains(url) {
            LaunchRequests.pending.append(url)
        }
        NotificationCenter.default.post(name: .openRepositoryRequest, object: nil)
        Self.ensureWindowForPendingRequests()
    }

    /// When launched with paths, SwiftUI skips its default window; open one so the request is handled.
    static func ensureWindowForPendingRequests() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
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
        NSWindow.allowsAutomaticWindowTabbing = true
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
            item.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem("Open Repository…") {
            NSApp.activate(ignoringOtherApps: true)
            if let url = RepoPicker.choose() { Self.openRepository(url) }
        })
        return menu
    }

    /// Brings an already open repository window to the front, or opens the repository in a window.
    static func openRepository(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let name = url.lastPathComponent
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == name }) {
            window.makeKeyAndOrderFront(nil)
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
struct FocusedRepoURLKey: FocusedValueKey { typealias Value = Binding<URL?> }

extension FocusedValues {
    var repoModel: RepoModel? {
        get { self[FocusedRepoKey.self] }
        set { self[FocusedRepoKey.self] = newValue }
    }
    var repoURL: Binding<URL?>? {
        get { self[FocusedRepoURLKey.self] }
        set { self[FocusedRepoURLKey.self] = newValue }
    }
}

// MARK: - Recent repositories

final class RecentRepos: ObservableObject {
    static let shared = RecentRepos()
    private let key = "recentRepositories"
    @Published private(set) var urls: [URL] = []

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        var list = urls.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        urls = Array(list.prefix(20))
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    func clear() {
        urls = []
        save()
    }

    private func save() { UserDefaults.standard.set(urls.map(\.path), forKey: key) }
}

enum RepoPicker {
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Repository"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Development aid: `SIDTREE_SNAPSHOT=/path/out.png` renders the main window to a PNG after launch.
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["SIDTREE_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["SIDTREE_SNAPSHOT_DELAY"] ?? "") ?? 3
        if ProcessInfo.processInfo.environment["SIDTREE_DEBUG_CLOSE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(delay - 1.5, 0.5)) {
                NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("repo-") == true && $0.isVisible }?.performClose(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let appearance = ProcessInfo.processInfo.environment["SIDTREE_APPEARANCE"] {
                NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if ProcessInfo.processInfo.environment["SIDTREE_DEBUG_WINDOWS"] != nil {
                    for w in NSApp.windows { FileHandle.standardError.write(Data("window id=\(w.identifier?.rawValue ?? "-") title=\(w.title) visible=\(w.isVisible)\n".utf8)) }
                }
                guard let main = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }),
                      case let window = main.attachedSheet ?? main,
                      let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
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
