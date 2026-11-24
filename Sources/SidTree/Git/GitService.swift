import Foundation

enum HistoryScope: String, CaseIterable, Identifiable {
    case all = "All Branches"
    case current = "Current Branch"
    var id: String { rawValue }
}

enum HistoryOrder: String, CaseIterable, Identifiable {
    case date = "Date Order"
    case ancestor = "Ancestor Order"
    var id: String { rawValue }
}

enum ResetMode: String, CaseIterable, Identifiable {
    case soft, mixed, hard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .soft: return "Soft – keep all local changes"
        case .mixed: return "Mixed – keep working copy, reset index"
        case .hard: return "Hard – discard all working copy changes"
        }
    }
}

/// All git operations for one repository.
struct GitService {
    let root: URL

    private func run(_ args: [String], input: Data? = nil) async -> GitResult {
        await GitRunner.run(args, in: root, input: input)
    }

    @discardableResult
    private func check(_ args: [String], input: Data? = nil) async throws -> GitResult {
        try await GitRunner.check(args, in: root, input: input)
    }

    // MARK: Discovery

    static func resolveRoot(of url: URL) async -> (root: URL, gitDir: URL)? {
        let top = await GitRunner.run(["rev-parse", "--show-toplevel", "--absolute-git-dir"], in: url)
        guard top.status == 0 else { return nil }
        let lines = top.output.split(separator: "\n").map(String.init)
        guard lines.count >= 2 else { return nil }
        return (URL(fileURLWithPath: lines[0]), URL(fileURLWithPath: lines[1]))
    }

    // MARK: Reading

    func log(scope: HistoryScope, showRemotes: Bool, order: HistoryOrder, limit: Int) async -> [Commit] {
        var args = ["log", "-z", "--decorate=full", "--max-count=\(limit)",
                    "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s"]
        args.append(order == .date ? "--date-order" : "--topo-order")
        switch scope {
        case .all:
            args += ["--branches", "--tags"]
            if showRemotes { args.append("--remotes") }
            args.append("HEAD")
        case .current:
            args.append("HEAD")
        }
        args.append("--")
        let result = await run(args)
        guard result.status == 0 else { return [] }
        return Parsers.parseLog(result.stdout)
    }

    func refs() async -> Parsers.RefsResult {
        let fmt = "%(refname)%00%(objectname)%00%(upstream:short)%00%(upstream:track,nobracket)%00%(HEAD)%00%(*objectname)"
        let result = await run(["for-each-ref", "--format=\(fmt)", "refs/heads", "refs/remotes", "refs/tags"])
        return Parsers.parseRefs(result.output)
    }

    func remotes() async -> [String] {
        let result = await run(["remote"])
        return result.output.split(separator: "\n").map(String.init)
    }

    func remoteURL(_ remote: String) async -> String? {
        let r = await run(["remote", "get-url", remote])
        return r.status == 0 ? r.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    /// Browser URL for a remote. Resolves ~/.ssh/config host aliases (e.g. `bitbucket.org-work`)
    /// via `ssh -G`, strips credentials and `.git`.
    func webURL(remote: String) async -> URL? {
        guard let raw = await remoteURL(remote) else { return nil }
        return await Self.webURL(fromRemote: raw)
    }

    static func webURL(fromRemote raw: String) async -> URL? {
        var host = ""
        var port: String?
        var path = ""
        var isSSH = false

        if let comps = URLComponents(string: raw), let scheme = comps.scheme, let h = comps.host {
            host = h
            path = comps.path
            isSSH = scheme.hasPrefix("ssh") || scheme == "git+ssh"
            if !isSSH, let p = comps.port { port = String(p) }
        } else if let colon = raw.firstIndex(of: ":") {
            // scp-like: [user@]host:path
            var hostPart = String(raw[..<colon])
            if let at = hostPart.lastIndex(of: "@") { hostPart = String(hostPart[hostPart.index(after: at)...]) }
            host = hostPart
            path = String(raw[raw.index(after: colon)...])
            isSSH = true
        } else {
            return nil
        }

        if isSSH { host = await resolveSSHHost(host) }
        for prefix in ["ssh.", "altssh."] where host.hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        if path.hasPrefix("/") { path.removeFirst() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        if path.hasSuffix("/") { path.removeLast() }
        // Self-hosted git over ssh often uses /scm/ or ~user paths; keep the path as-is.
        let hostPort = port.map { "\(host):\($0)" } ?? host
        return URL(string: "https://\(hostPort)/\(path)")
    }

    private static func resolveSSHHost(_ alias: String) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                p.arguments = ["-G", alias]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                p.standardInput = FileHandle.nullDevice
                guard (try? p.run()) != nil else { cont.resume(returning: alias); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                let hostname = text.split(separator: "\n")
                    .first { $0.hasPrefix("hostname ") }
                    .map { String($0.dropFirst("hostname ".count)).trimmingCharacters(in: .whitespaces) }
                cont.resume(returning: hostname?.isEmpty == false ? hostname! : alias)
            }
        }
    }

    // MARK: Performance helpers

    func hasCommitGraph() async -> Bool {
        let r = await run(["rev-parse", "--git-path", "objects/info"])
        let dir = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = dir.hasPrefix("/") ? URL(fileURLWithPath: dir) : root.appendingPathComponent(dir)
        let fm = FileManager.default
        return fm.fileExists(atPath: base.appendingPathComponent("commit-graph").path)
            || fm.fileExists(atPath: base.appendingPathComponent("commit-graphs").path)
    }

    func writeCommitGraph() async throws {
        try await check(["commit-graph", "write", "--reachable", "--split"])
    }

    /// Ignored paths at directory granularity (directories end with "/"), used to filter file-system events.
    func ignoredPaths() async -> Set<String> {
        let r = await run(["status", "--porcelain=v1", "-z", "--ignored=matching", "--untracked-files=normal"])
        var set = Set<String>()
        for entry in Parsers.splitNul(r.stdout) where entry.hasPrefix("!! ") {
            set.insert(String(entry.dropFirst(3)))
        }
        return set
    }

    func status() async -> StatusSnapshot {
        let result = await run(["status", "--porcelain=v2", "-z", "--branch", "--untracked-files=all", "--ignore-submodules=dirty"])
        return Parsers.parseStatus(result.stdout)
    }

    func stashes() async -> [Stash] {
        let result = await run(["stash", "list", "-z", "--format=%gd%x1f%H%x1f%at%x1f%gs"])
        return Parsers.parseStashes(result.stdout)
    }

    func repoState(gitDir: URL) -> RepoState {
        let fm = FileManager.default
        func exists(_ p: String) -> Bool { fm.fileExists(atPath: gitDir.appendingPathComponent(p).path) }
        if exists("rebase-merge") || exists("rebase-apply") { return .rebasing }
        if exists("MERGE_HEAD") { return .merging }
        if exists("CHERRY_PICK_HEAD") { return .cherryPicking }
        if exists("REVERT_HEAD") { return .reverting }
        return .normal
    }

    /// When the parents are already known (from the log) the message and file list load in parallel.
    func commitDetail(_ hash: String, knownParents: [String]? = nil) async -> CommitDetail? {
        async let show = run(["show", "-s", "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%cn%x1f%ce%x1f%B", hash])
        async let prefetched: [FileChange]? = knownParents == nil ? nil : changedFiles(hash, parents: knownParents!)
        let r = await show
        guard r.status == 0 else { return nil }
        let f = r.output.split(separator: Parsers.fieldSep, maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
        guard f.count == 8 else { return nil }
        let parents = f[1].split(separator: " ").map(String.init)
        let files: [FileChange]
        if let pre = await prefetched, knownParents == parents { files = pre } else { files = await changedFiles(hash, parents: parents) }
        return CommitDetail(hash: f[0], parents: parents, author: f[2], authorEmail: f[3],
                            authorDate: Date(timeIntervalSince1970: TimeInterval(f[4]) ?? 0),
                            committer: f[5], committerEmail: f[6],
                            message: f[7].trimmingCharacters(in: .whitespacesAndNewlines), files: files)
    }

    func changedFiles(_ hash: String, parents: [String]) async -> [FileChange] {
        let args: [String]
        if parents.count > 1 {
            args = ["diff", "-z", "--name-status", "-M", parents[0], hash]
        } else {
            args = ["diff-tree", "-r", "-z", "--no-commit-id", "--name-status", "-M", "--root", hash]
        }
        return Parsers.parseNameStatus(await run(args).stdout)
    }

    func lastCommitMessage() async -> String {
        await run(["log", "-1", "--format=%B"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Diffs

    static let maxDiffBytes = 4_000_000

    private func diff(_ args: [String]) async -> FileDiff {
        let result = await run(args)
        if result.stdout.count > Self.maxDiffBytes {
            var d = FileDiff(); d.tooLarge = true; return d
        }
        return Parsers.parseDiff(result.output)
    }

    func workingDiff(_ file: FileChange) async -> FileDiff {
        if file.kind == .untracked {
            return await diff(["diff", "--no-ext-diff", "--no-index", "--", "/dev/null", file.path])
        }
        var args = ["diff", "--no-ext-diff", "-M", "-U3"]
        if file.staged { args.append("--cached") }
        args.append("--")
        if let orig = file.originalPath { args.append(orig) }
        args.append(file.path)
        return await diff(args)
    }

    func commitDiff(_ hash: String, parents: [String], file: FileChange) async -> FileDiff {
        var args: [String]
        if let p = parents.first {
            args = ["diff", "--no-ext-diff", "-M", "-U3", p, hash]
        } else {
            args = ["show", "--no-ext-diff", "--format=", "-M", "-U3", hash]
        }
        args.append("--")
        if let orig = file.originalPath { args.append(orig) }
        args.append(file.path)
        return await diff(args)
    }

    // MARK: Index operations

    func stage(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await check(["add", "-A", "--"] + paths)
    }

    func stageAll() async throws { try await check(["add", "-A"]) }

    func unstage(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let r = await run(["restore", "--staged", "--"] + paths)
        if r.status != 0 {
            // Unborn branch: there is no HEAD to restore from.
            try await check(["rm", "--cached", "-r", "-q", "--"] + paths)
        }
    }

    func unstageAll() async throws {
        let r = await run(["reset", "-q"])
        if r.status != 0 { try await check(["rm", "--cached", "-r", "-q", "."]) }
    }

    /// Discards all changes (staged and unstaged) for the given files.
    func discard(_ files: [FileChange]) async throws {
        let untracked = files.filter { $0.kind == .untracked }
        let tracked = files.filter { $0.kind != .untracked }.map(\.path)
        for f in untracked {
            let url = root.appendingPathComponent(f.path)
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        if !tracked.isEmpty {
            let r = await run(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + tracked)
            if r.status != 0 {
                // Newly added (staged) files have no HEAD version: drop them from the index and trash them.
                try await check(["rm", "-f", "-q", "--"] + tracked)
            }
        }
    }

    func applyPatch(_ patch: String, cached: Bool, reverse: Bool) async throws {
        var args = ["apply", "--whitespace=nowarn"]
        if cached { args.append("--cached") }
        if reverse { args.append("-R") }
        args.append("-")
        try await check(args, input: Data(patch.utf8))
    }

    // MARK: Commit

    func commit(message: String, amend: Bool) async throws {
        var args = ["commit", "-F", "-"]
        if amend { args.append("--amend") }
        try await check(args, input: Data(message.utf8))
    }

    // MARK: Remote

    func fetch(prune: Bool = true) async throws {
        // Keep the commit-graph up to date incrementally so history stays fast after fetching.
        var args = ["-c", "fetch.writeCommitGraph=true", "fetch", "--all", "--tags"]
        if prune { args.append("--prune") }
        try await check(args)
    }

    func pull(remote: String, branch: String?, rebase: Bool, commit: Bool) async throws {
        var args = ["pull", rebase ? "--rebase" : "--no-rebase"]
        if !commit && !rebase { args.append("--no-commit") }
        args.append(remote)
        if let branch { args.append(branch) }
        try await check(args)
    }

    struct PushSpec { let local: String; let remote: String }

    func push(remote: String, specs: [PushSpec], setUpstream: Bool, tags: Bool, force: Bool) async throws {
        var args = ["push", "--porcelain"]
        if setUpstream { args.append("--set-upstream") }
        if force { args.append("--force-with-lease") }
        args.append(remote)
        args += specs.map { "refs/heads/\($0.local):refs/heads/\($0.remote)" }
        if tags { args.append("--tags") }
        try await check(args)
    }

    func pushTag(_ tag: String, remote: String) async throws {
        try await check(["push", remote, "refs/tags/\(tag)"])
    }

    // MARK: Branches

    func checkout(_ branch: String) async throws {
        try await check(["switch", branch])
    }

    func checkoutRemote(_ remoteBranch: Branch, localName: String) async throws {
        try await check(["switch", "-c", localName, "--track", remoteBranch.name])
    }

    func checkoutDetached(_ hash: String) async throws {
        try await check(["switch", "--detach", hash])
    }

    func createBranch(_ name: String, from start: String?, checkout: Bool) async throws {
        if checkout {
            var args = ["switch", "-c", name]
            if let start { args.append(start) }
            try await check(args)
        } else {
            var args = ["branch", name]
            if let start { args.append(start) }
            try await check(args)
        }
    }

    func deleteBranch(_ name: String, force: Bool) async throws {
        try await check(["branch", force ? "-D" : "-d", name])
    }

    func deleteRemoteBranch(remote: String, name: String) async throws {
        try await check(["push", remote, "--delete", name])
    }

    func renameBranch(_ old: String, to new: String) async throws {
        try await check(["branch", "-m", old, new])
    }

    func merge(_ ref: String, noFF: Bool, commit: Bool, squash: Bool) async throws {
        var args = ["merge"]
        if squash { args.append("--squash") }
        else {
            if noFF { args.append("--no-ff") }
            if !commit { args += ["--no-commit", "--no-ff"] }
        }
        args.append(ref)
        try await check(args)
    }

    func rebase(onto ref: String) async throws { try await check(["rebase", ref]) }

    func abortMerge() async throws { try await check(["merge", "--abort"]) }
    func abortRebase() async throws { try await check(["rebase", "--abort"]) }
    func continueRebase() async throws {
        let r = await GitRunner.run(["-c", "core.editor=true", "rebase", "--continue"], in: root)
        if r.status != 0 { throw GitError(command: "git rebase --continue", message: r.errorOutput.isEmpty ? r.output : r.errorOutput) }
    }
    func abortCherryPick() async throws { try await check(["cherry-pick", "--abort"]) }
    func abortRevert() async throws { try await check(["revert", "--abort"]) }

    func resolve(_ path: String, ours: Bool) async throws {
        try await check(["checkout", ours ? "--ours" : "--theirs", "--", path])
        try await check(["add", "--", path])
    }

    // MARK: Commits

    func reset(to hash: String, mode: ResetMode) async throws { try await check(["reset", "--\(mode.rawValue)", hash]) }
    func revert(_ hash: String, isMerge: Bool) async throws {
        var args = ["revert", "--no-edit"]
        if isMerge { args += ["-m", "1"] }
        args.append(hash)
        try await check(args)
    }
    func cherryPick(_ hash: String) async throws { try await check(["cherry-pick", hash]) }

    func createTag(_ name: String, at hash: String, message: String?) async throws {
        if let message, !message.isEmpty {
            try await check(["tag", "-a", name, "-m", message, hash])
        } else {
            try await check(["tag", name, hash])
        }
    }
    func deleteTag(_ name: String) async throws { try await check(["tag", "-d", name]) }

    // MARK: Stash

    func stash(message: String, keepIndex: Bool, includeUntracked: Bool) async throws {
        var args = ["stash", "push"]
        if keepIndex { args.append("--keep-index") }
        if includeUntracked { args.append("--include-untracked") }
        if !message.isEmpty { args += ["-m", message] }
        try await check(args)
    }
    func applyStash(_ ref: String, pop: Bool) async throws { try await check(["stash", pop ? "pop" : "apply", "--index", ref]) }
    func dropStash(_ ref: String) async throws { try await check(["stash", "drop", ref]) }
}
