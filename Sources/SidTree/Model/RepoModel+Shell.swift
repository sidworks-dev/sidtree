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

    func open(_ file: FileChange) {
        NSWorkspace.shared.open(root.appendingPathComponent(file.path))
    }

    func reveal(_ file: FileChange) {
        NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(file.path)])
    }
}
