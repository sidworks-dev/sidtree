import AppKit

extension RepoModel {
    // MARK: - Shell helpers

    func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([root]) }

    func openTerminal() {
        let app = UserDefaults.standard.string(forKey: "terminalApp") ?? "Terminal"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", app.isEmpty ? "Terminal" : app, root.path]
        try? p.run()
    }

    /// The remote the current branch tracks, else `origin`, else the first remote.
    var preferredRemote: String? {
        if let up = Self.splitUpstream(currentBranchInfo?.upstream), remotes.contains(up.0) { return up.0 }
        if remotes.contains("origin") { return "origin" }
        return remotes.first
    }

    func openRemoteInBrowser() {
        Task {
            guard let remote = preferredRemote else { return }
            if let url = await git.webURL(remote: remote) {
                NSWorkspace.shared.open(url)
            } else {
                self.error = GitError(command: "open remote", message: "Could not derive a web address for remote '\(remote)'.")
            }
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Copied")
    }

    /// Opens the file with its default app. Files that could run code (apps, `.command`, executables, links
    /// out of the repository) go to the code editor instead, or are shown in Finder.
    func open(_ file: FileChange) {
        let url = root.appendingPathComponent(file.path)
        if let reason = FileSafety.blockReason(url, root: root) {
            if EditorSettings.open([url]) {
                showToast("Opened in \(EditorSettings.current?.name ?? "editor") because \(reason)")
            } else {
                reveal(file)
                showToast("Shown in Finder because \(reason)")
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Opens the repository, or the given files, in the code editor chosen in Settings.
    func openInEditor(_ files: [FileChange] = []) {
        let urls = files.isEmpty ? [root] : files.map { root.appendingPathComponent($0.path) }
        if !EditorSettings.open(urls) {
            UserDefaults.standard.set("tools", forKey: "settings.tab")
            NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
            showToast("Choose an editor in Settings → Tools")
        }
    }

    var editorName: String { EditorSettings.current?.name ?? "Editor" }

    /// Opens the working-copy file at a line in the chosen editor.
    func openInEditor(path: String, line: Int) {
        let url = root.appendingPathComponent(path)
        if !EditorSettings.open(url, line: line) { openInEditor() }
    }

    func reveal(_ file: FileChange) {
        NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(file.path)])
    }
}
