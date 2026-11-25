import Foundation

extension RepoModel {
    /// Runs a fetch, pull or push while its toolbar button shows a spinner.
    func whileSyncing<T>(_ action: SyncAction, _ op: () async throws -> T) async rethrows -> T {
        syncing.insert(action)
        defer { syncing.remove(action) }
        return try await op()
    }

    /// Runs a push while the pushed branches show a spinner in the sidebar and the Push button shows one too.
    func whilePushing<T>(_ branches: [String], _ op: () async throws -> T) async rethrows -> T {
        pushingBranches.formUnion(branches)
        defer { pushingBranches.subtract(branches) }
        return try await whileSyncing(.push, op)
    }

    /// Deletes a local branch and, if asked, its branch on the remote.
    /// Without force, git refuses unmerged branches; the user can then choose to force it.
    func deleteLocalBranch(_ name: String, force: Bool, remote: (remote: String, branch: String)?) {
        let done = remote.map { "Deleted \(name) and \($0.remote)/\($0.branch)" } ?? "Deleted \(name)"
        perform("Deleting \(name)…") {
            do {
                try await self.git.deleteBranch(name, force: force)
            } catch let e as GitError where !force && e.message.contains("not fully merged") {
                await MainActor.run {
                    self.confirm = ConfirmRequest(title: "\(name) is not fully merged",
                                                  message: "Force delete it anyway? Its unmerged commits will be lost.",
                                                  actionTitle: "Force Delete") { [self] in
                        deleteLocalBranch(name, force: true, remote: remote)
                    }
                }
                return
            }
            if let remote { try await self.git.deleteRemoteBranch(remote: remote.remote, name: remote.branch) }
            await MainActor.run { self.showToast(done) }
        }
    }
}
