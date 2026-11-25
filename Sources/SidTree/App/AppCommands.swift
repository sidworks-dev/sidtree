import AppKit
import SwiftUI

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.repoModel) private var model
    @FocusedValue(\.workspace) private var workspace
    @ObservedObject private var recent = RecentRepos.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "repo") }
                .keyboardShortcut("n")
            Button("New Tab") { workspace?.showOverview() }
                .keyboardShortcut("t")
                .disabled(workspace == nil)
            Divider()
            Button("Open…") {
                if let url = RepoPicker.choose() { open(url) }
            }
            .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(recent.urls, id: \.self) { url in
                    Button(url.lastPathComponent + "  —  " + DisplayPath.parent(of: url)) {
                        open(url)
                    }
                }
                if !recent.urls.isEmpty { Divider() }
                Button("Clear Menu") { recent.clear() }
                    .disabled(recent.urls.isEmpty)
            }
            Divider()
            // Comes before the standard Close item, so ⌘W closes the tab first and the window once no tab is shown.
            Button("Close Tab") { if let workspace, let id = workspace.activeID { workspace.close(id) } }
                .keyboardShortcut("w")
                .disabled(workspace?.activeID == nil)
        }

        CommandGroup(before: .windowList) {
            Button("Show Next Tab") { workspace?.cycle(1) }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled((workspace?.tabs.isEmpty ?? true))
            Button("Show Previous Tab") { workspace?.cycle(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled((workspace?.tabs.isEmpty ?? true))
            Divider()
        }

        CommandGroup(after: .sidebar) {
            Button("Changes") { model?.sidebarSelection = .changes }
                .keyboardShortcut("1")
                .disabled(model == nil)
            Button("History") { model?.sidebarSelection = .history }
                .keyboardShortcut("2")
                .disabled(model == nil)
            Divider()
            Button("Refresh") { Task { await model?.refreshAll() } }
                .keyboardShortcut("r")
                .disabled(model == nil)
        }

        CommandGroup(after: .appInfo) {
            Button("Install Command Line Tools…") { CommandLineTools.install() }
            Divider()
            Button("Check for Updates…") {
                openWindow(id: "update")
                Task { await UpdateChecker.shared.check(userInitiated: true) }
            }
        }

        CommandGroup(replacing: .help) {
            Button("What's New in SidTree") { openWindow(id: "whats-new") }
            Button("SidTree on GitHub") { NSWorkspace.shared.open(UpdateChecker.repoURL) }
        }

        CommandMenu("Repository") {
            Button("Commit…") { model?.requestCommit() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Pull…") { model?.sheet = .pull }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Push…") { model?.sheet = .push }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Fetch") { model?.fetch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("New Branch…") { model?.sheet = .newBranch(startPoint: nil) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Delete Branches…") { model?.sheet = .deleteBranches }
            Button("Merge…") { model?.sheet = .merge(nil) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Stash…") { model?.sheet = .stash }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("New Tag…") { model?.sheet = .tag(nil) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Open in Editor") { model?.openInEditor() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Show in Finder") { model?.showInFinder() }
            Button("Open in Terminal") { model?.openTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Open Remote in Browser") { model?.openRemoteInBrowser() }
        }
    }

    private func open(_ url: URL) {
        if let workspace {
            workspace.open(url)
        } else {
            AppDelegate.openRepository(url)
        }
    }
}
