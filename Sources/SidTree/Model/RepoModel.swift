import AppKit
import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case fileStatus
    case history
    case branch(String)
    case remoteBranch(String)
    case tag(String)
    case stash(String)
}

enum SheetKind: Identifiable {
    case push
    case pull
    case newBranch(startPoint: String?)
    case deleteBranches
    case renameBranch(String)
    case merge(String?)
    case rebase(String)
    case stash
    case tag(String?)
    case reset(String)

    var id: String {
        switch self {
        case .push: return "push"
        case .pull: return "pull"
        case .newBranch(let s): return "newBranch-\(s ?? "")"
        case .deleteBranches: return "deleteBranches"
        case .renameBranch(let b): return "rename-\(b)"
        case .merge(let b): return "merge-\(b ?? "")"
        case .rebase(let b): return "rebase-\(b)"
        case .stash: return "stash"
        case .tag(let c): return "tag-\(c ?? "")"
        case .reset(let c): return "reset-\(c)"
        }
    }
}

struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    var destructive = true
    let action: () -> Void
}

struct HistoryRow {
    let commit: Commit
    let graph: GraphRow
}

@MainActor
@Observable
final class RepoModel {
    let root: URL
    let gitDir: URL
    let git: GitService
    var name: String { root.lastPathComponent }

    // Refs
    var localBranches: [Branch] = []
    var remoteBranches: [Branch] = []
    var tags: [Tag] = []
    var remotes: [String] = []
    var stashes: [Stash] = []

    // Working copy
    var status = StatusSnapshot()
    var repoState: RepoState = .normal
    var currentBranch: String? { status.branch }
    var hasLocalChanges: Bool { !status.staged.isEmpty || !status.unstaged.isEmpty }
    var changeCount: Int { Set(status.staged.map(\.path) + status.unstaged.map(\.path)).count }
    var currentBranchInfo: Branch? { localBranches.first { $0.isHead } }

    // History
    private(set) var rows: [HistoryRow] = []
    private(set) var displayRows: [HistoryRow] = []
    private(set) var historyVersion = 0
    private(set) var commitCount = 0
    /// commit id → index in `rows`
    private(set) var rowIndex: [String: Int] = [:]
    private var loadedCommits: [Commit] = []
    private var historyGeneration = 0
    private var layoutGeneration = 0
    var historyLoading = false
    var canLoadMore = false
    var historyScope: HistoryScope = .all { didSet { reloadHistorySoon() } }
    var showRemotes = true { didSet { reloadHistorySoon() } }
    var historyOrder: HistoryOrder = .date { didSet { reloadHistorySoon() } }
    var historySearch = "" { didSet { applyHistoryFilter() } }
    var historyLimit = 10000

    var selectedCommitID: String?
    var scrollRequest: (id: String, token: Int)?
    var commitDetail: CommitDetail?
    var selectedCommitFile: FileChange?
    var commitDiff: FileDiff?
    var commitDiffLoading = false
    private var detailGeneration = 0

    // File status
    var selectedStatusFile: FileChange?
    var statusDiff: FileDiff?
    var commitMessage = ""
    var amend = false { didSet { amendChanged(oldValue) } }
    var pushAfterCommit = false {
        didSet { RepositoryCommitSettings.save(pushAfterCommit: pushAfterCommit, for: root) }
    }
    var commitFocusToken = 0
    var aiGenerating = false
    private var savedMessageBeforeAmend = ""
    private var statusDiffGeneration = 0

    // UI state
    var sidebarSelection: SidebarItem? = .history { didSet { sidebarChanged() } }
    var sheet: SheetKind?
    var confirm: ConfirmRequest?
    /// The problem currently shown to the user.
    var problem: ProblemReport?

    /// Setting an error shows it as a readable problem report.
    var error: GitError? {
        get { nil }
        set {
            guard let e = newValue else { return }
            problem = ProblemInterpreter.report(for: e.message, label: e.command, model: self, retry: nil, stashAndRetry: nil)
        }
    }
    var activity: String?
    var toast: String?
    var sidebarFilter = ""

    // Infra
    private var watcher: RepoWatcher?
    private var opChain: Task<Void, Never>?
    private var opsRunning = 0
    private var pendingChange: RepoWatcher.Change = []
    private var debounceTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var autoFetchTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var activeObserver: NSObjectProtocol?
    private var scrollToken = 0

    static let trace = ProcessInfo.processInfo.environment["SIDTREE_TRACE"] != nil
    private let createdAt = Date()

    init(root: URL, gitDir: URL) {
        self.root = root
        self.gitDir = gitDir
        self.git = GitService(root: root)
        let defaults = UserDefaults.standard
        pushAfterCommit = RepositoryCommitSettings.pushesAfterCommit(for: root, defaults: defaults)
        historyLimit = max(500, defaults.integer(forKey: "historyLimit") == 0 ? 10000 : defaults.integer(forKey: "historyLimit"))
        if defaults.object(forKey: "showRemoteBranches") != nil {
            showRemotes = defaults.bool(forKey: "showRemoteBranches")
        }
    }

    func start() {
        Task {
            await refreshAll(firstPage: 400)
            await optimizeInBackground()
        }
        watcher = RepoWatcher(root: root, gitDir: gitDir) { [weak self] change in
            self?.fileSystemChanged(change)
        }
        watcher?.start()
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.appBecameActive() }
        }
        scheduleAutoFetch()
        if let view = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_VIEW"] {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let branch = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_CHECKOUT"] {
                    checkout(localName: branch)
                    return
                }
                let wanted = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_SELECT"] ?? ""
                if view == "status" {
                    sidebarSelection = .fileStatus
                    selectStatusFile(status.staged.first ?? status.unstaged.first)
                } else if !wanted.isEmpty, let row = rows.first(where: { $0.commit.subject.contains(wanted) }) {
                    selectCommit(row.commit.id)
                } else if rows.count > 2 {
                    selectCommit(rows[2].commit.id)
                }
            }
        }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        autoFetchTask?.cancel()
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }

    // MARK: - Refreshing

    /// Loads refs, status, stashes, remotes and history in parallel and applies them in one go.
    /// `firstPage` limits the history for a fast first paint (the caller loads the rest afterwards).
    func refreshAll(firstPage: Int? = nil) async {
        historyGeneration += 1
        let gen = historyGeneration
        let limit = firstPage ?? historyLimit
        // Everything starts at once; results are applied as soon as each arrives so a slow
        // `git status` (large working copies) never delays the history.
        let git = self.git
        let statusTask = Task.detached(priority: .userInitiated) { await git.status() }
        async let refs = git.refs()
        async let stashes = git.stashes()
        async let remotes = git.remotes()
        async let log = git.log(scope: historyScope, showRemotes: showRemotes, order: historyOrder, limit: limit)

        let r = await refs
        if localBranches != r.local { localBranches = r.local }
        if remoteBranches != r.remote { remoteBranches = r.remote }
        if tags != r.tags { tags = r.tags }
        let commits = await log
        if gen == historyGeneration {
            applyLog(commits, limit: limit, forceRebuild: false)
            // First page is on screen; fetch the full history right away without waiting for status.
            if firstPage != nil, commits.count >= limit { Task { await loadHistory() } }
        }
        let (st, rm) = await (stashes, remotes)
        if self.stashes != st { self.stashes = st }
        if self.remotes != rm { self.remotes = rm }

        let s = await statusTask.value
        let wasDirty = hasLocalChanges
        applyStatus(s)
        if wasDirty != hasLocalChanges { rebuildRows() }
    }

    func refreshStatus() async {
        let s = await git.status()
        let wasDirty = hasLocalChanges
        applyStatus(s)
        if wasDirty != hasLocalChanges { rebuildRows() }
    }

    private func applyStatus(_ s: StatusSnapshot) {
        let stagedChanged = status.staged != s.staged
        if status != s { status = s }
        if stagedChanged { prepareCommitMessageSoon() }
        let state = git.repoState(gitDir: gitDir)
        if repoState != state { repoState = state }
        // Keep the selected file in sync with the fresh status.
        if let sel = selectedStatusFile {
            let list = sel.staged ? s.staged : s.unstaged
            if let match = list.first(where: { $0.path == sel.path }) {
                selectedStatusFile = match
                loadStatusDiff()
            } else if let other = (sel.staged ? s.unstaged : s.staged).first(where: { $0.path == sel.path }) {
                selectedStatusFile = other
                loadStatusDiff()
            } else {
                selectedStatusFile = nil
                statusDiff = nil
            }
        }
        if selectedCommitID == workingCopyID { loadCommitDetail() }
    }

    func loadHistory() async {
        historyGeneration += 1
        let gen = historyGeneration
        historyLoading = true
        let limit = historyLimit
        let commits = await git.log(scope: historyScope, showRemotes: showRemotes, order: historyOrder, limit: limit)
        guard gen == historyGeneration else { return }
        applyLog(commits, limit: limit, forceRebuild: false)
        historyLoading = false
    }

    /// Skips graph layout and table reload entirely when nothing changed (the common case after a refresh).
    private func applyLog(_ commits: [Commit], limit: Int, forceRebuild: Bool) {
        canLoadMore = commits.count >= limit
        if !forceRebuild && !rows.isEmpty && commits == loadedCommits { return }
        loadedCommits = commits
        rebuildRows()
    }

    /// One-time repository tuning that makes history queries much faster:
    /// a commit-graph turns `git log --date-order -n 500` from a full history walk (~200ms) into ~15ms.
    private func optimizeInBackground() async {
        await refreshIgnoredPaths()
        guard UserDefaults.standard.object(forKey: "optimizeRepositories") as? Bool ?? true else { return }
        if await !git.hasCommitGraph() {
            try? await git.writeCommitGraph()
            if Self.trace { FileHandle.standardError.write(Data((String(format: "[trace] commit-graph written at %.0fms", Date().timeIntervalSince(createdAt) * 1000) + "\n").utf8)) }
        }
    }

    func refreshIgnoredPaths() async {
        let ignored = await git.ignoredPaths()
        watcher?.setIgnored(ignored)
    }

    func loadMoreHistory() {
        guard canLoadMore, !historyLoading else { return }
        historyLimit += 5000
        Task { await loadHistory() }
    }

    private func reloadHistorySoon() {
        UserDefaults.standard.set(showRemotes, forKey: "showRemoteBranches")
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await loadHistory()
        }
    }

    private func rebuildRows() {
        var commits = loadedCommits
        if hasLocalChanges, let head = status.headOID ?? loadedCommits.first?.id {
            let wc = Commit(id: workingCopyID, parents: [head], author: "", email: "", date: Date(),
                            subject: "Uncommitted changes", refs: [])
            commits.insert(wc, at: 0)
        }
        layoutGeneration += 1
        let gen = layoutGeneration
        Task {
            let graph = await Task.detached(priority: .userInitiated) { GraphLayout.layout(commits) }.value
            guard gen == self.layoutGeneration else { return }
            self.rows = zip(commits, graph).map { HistoryRow(commit: $0, graph: $1) }
            if Self.trace { FileHandle.standardError.write(Data((String(format: "[trace] rows=%d at %.0fms", self.rows.count, Date().timeIntervalSince(self.createdAt) * 1000) + "\n").utf8)) }
            var index: [String: Int] = [:]
            index.reserveCapacity(self.rows.count)
            for (i, row) in self.rows.enumerated() { index[row.commit.id] = i }
            self.rowIndex = index
            self.applyHistoryFilter()
            if let sel = self.selectedCommitID, self.rowIndex[sel] == nil {
                self.selectedCommitID = nil
                self.commitDetail = nil
                self.commitDiff = nil
            }
        }
    }

    private func applyHistoryFilter() {
        let q = historySearch.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            displayRows = rows
        } else {
            let lower = q.lowercased()
            displayRows = rows.filter { row in
                let c = row.commit
                return c.id.hasPrefix(lower)
                    || c.subject.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || c.author.range(of: q, options: .caseInsensitive) != nil
                    || c.refs.contains { $0.name.range(of: q, options: .caseInsensitive) != nil }
            }
        }
        commitCount = displayRows.count - (displayRows.first?.commit.isWorkingCopy == true ? 1 : 0)
        historyVersion += 1
    }

    var isFilteringHistory: Bool { !historySearch.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - File system events

    private func fileSystemChanged(_ change: RepoWatcher.Change) {
        pendingChange.formUnion(change)
        guard opsRunning == 0 else { return }
        guard NSApp.isActive else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await flushPendingChanges()
        }
    }

    private func flushPendingChanges() async {
        let change = pendingChange
        pendingChange = []
        if change.contains(.ignoreRules) { await refreshIgnoredPaths() }
        if change.contains(.refs) {
            await refreshAll()
        } else if change.contains(.workingCopy) {
            await refreshStatus()
        }
    }

    private func appBecameActive() {
        if !pendingChange.isEmpty, opsRunning == 0 {
            Task { await flushPendingChanges() }
        }
    }

    private func scheduleAutoFetch() {
        autoFetchTask?.cancel()
        autoFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = UserDefaults.standard.object(forKey: "autoFetchMinutes") as? Int ?? 10
                try? await Task.sleep(nanoseconds: UInt64(max(minutes, 1)) * 60 * 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if minutes > 0, self.opsRunning == 0, !self.remotes.isEmpty {
                    try? await self.git.fetch()
                    await self.refreshAll()
                }
            }
        }
    }

    // MARK: - Operations

    /// Runs git operations one after another, shows progress, reports errors and refreshes afterwards.
    func perform(_ label: String, success: String? = nil, refresh: Bool = true, _ op: @escaping () async throws -> Void) {
        let previous = opChain
        opsRunning += 1
        opChain = Task {
            await previous?.value
            self.activity = label
            do {
                try await op()
                if let success { self.showToast(success) }
            } catch {
                let message = (error as? GitError)?.message ?? error.localizedDescription
                self.problem = ProblemInterpreter.report(
                    for: message, label: label, model: self,
                    retry: { [unowned self] in self.perform(label, success: success, refresh: refresh, op) },
                    stashAndRetry: { [unowned self] in
                        self.perform("Stashing changes…", success: success, refresh: refresh) {
                            try await self.git.stash(message: "SidTree: before \(label.replacingOccurrences(of: "…", with: "").lowercased())",
                                                     keepIndex: false, includeUntracked: true)
                            try await op()
                        }
                    })
            }
            self.pendingChange = []
            if refresh { await self.refreshAll() }
            self.opsRunning -= 1
            if self.opsRunning == 0 { self.activity = nil }
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self.toast = nil }
        }
    }

    func fetch() {
        perform("Fetching…", success: "Fetched all remotes") { try await self.git.fetch() }
    }

    func checkout(branch: Branch) {
        if branch.isRemote {
            if let local = localBranches.first(where: { $0.upstream == branch.name }) ?? localBranches.first(where: { $0.name == branch.shortName }) {
                guard !local.isHead else { return }
                perform("Checking out \(local.name)…", success: "Switched to \(local.name)") { try await self.git.checkout(local.name) }
            } else {
                perform("Checking out \(branch.shortName)…", success: "Created \(branch.shortName) tracking \(branch.name)") {
                    try await self.git.checkoutRemote(branch, localName: branch.shortName)
                }
            }
        } else {
            guard !branch.isHead else { return }
            perform("Checking out \(branch.name)…", success: "Switched to \(branch.name)") { try await self.git.checkout(branch.name) }
        }
    }

    func checkout(localName name: String) {
        if let b = localBranches.first(where: { $0.name == name }) { checkout(branch: b) }
    }

    func checkoutDetached(_ hash: String) {
        confirm = ConfirmRequest(
            title: "Checkout commit \(hash.prefix(8))?",
            message: "You will be in 'detached HEAD' state. Create a branch if you want to keep commits made from here.",
            actionTitle: "Checkout", destructive: false
        ) { [self] in
            perform("Checking out…", success: "HEAD detached at \(hash.prefix(8))") { try await self.git.checkoutDetached(hash) }
        }
    }

    func deleteBranch(_ branch: Branch) {
        if branch.isRemote, let remote = branch.remoteName {
            confirm = ConfirmRequest(title: "Delete remote branch \(branch.name)?",
                                     message: "The branch '\(branch.shortName)' will be deleted on '\(remote)'. This cannot be undone.",
                                     actionTitle: "Delete") { [self] in
                perform("Deleting \(branch.name)…", success: "Deleted \(branch.name)") {
                    try await self.git.deleteRemoteBranch(remote: remote, name: branch.shortName)
                }
            }
        } else {
            confirm = ConfirmRequest(title: "Delete branch \(branch.name)?",
                                     message: "Unmerged commits on this branch would be lost; git refuses unless they are merged.",
                                     actionTitle: "Delete") { [self] in
                perform("Deleting \(branch.name)…", success: "Deleted \(branch.name)") {
                    do { try await self.git.deleteBranch(branch.name, force: false) } catch let e as GitError where e.message.contains("not fully merged") {
                        await MainActor.run {
                            self.confirm = ConfirmRequest(title: "\(branch.name) is not fully merged",
                                                          message: "Force delete it anyway? Its unmerged commits will be lost.",
                                                          actionTitle: "Force Delete") { [self] in
                                perform("Deleting \(branch.name)…", success: "Deleted \(branch.name)") {
                                    try await self.git.deleteBranch(branch.name, force: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func deleteTag(_ tag: Tag) {
        confirm = ConfirmRequest(title: "Delete tag \(tag.name)?", message: "The tag is removed locally only.", actionTitle: "Delete") { [self] in
            perform("Deleting tag…", success: "Deleted tag \(tag.name)") { try await self.git.deleteTag(tag.name) }
        }
    }

    func revert(_ commit: Commit) {
        confirm = ConfirmRequest(title: "Revert commit \(commit.shortHash)?",
                                 message: "A new commit that undoes “\(commit.subject)” will be created.",
                                 actionTitle: "Revert", destructive: false) { [self] in
            perform("Reverting…", success: "Reverted \(commit.shortHash)") { try await self.git.revert(commit.id, isMerge: commit.isMerge) }
        }
    }

    func cherryPick(_ commit: Commit) {
        perform("Cherry-picking…", success: "Cherry-picked \(commit.shortHash)") { try await self.git.cherryPick(commit.id) }
    }

    // Stash
    func applyStash(_ stash: Stash, pop: Bool) {
        perform(pop ? "Popping stash…" : "Applying stash…", success: pop ? "Stash popped" : "Stash applied") {
            do { try await self.git.applyStash(stash.ref, pop: pop) } catch {
                // Retry without restoring the index (fails when the index changed in between).
                let args = ["stash", pop ? "pop" : "apply", stash.ref]
                try await GitRunner.check(args, in: self.root)
            }
        }
    }

    func dropStash(_ stash: Stash) {
        confirm = ConfirmRequest(title: "Delete stash?", message: "“\(stash.message)” will be deleted permanently.", actionTitle: "Delete") { [self] in
            perform("Deleting stash…", success: "Stash deleted") { try await self.git.dropStash(stash.ref) }
        }
    }

    // Merge / rebase state
    func abortOperation() {
        let state = repoState
        confirm = ConfirmRequest(title: "Abort?", message: "All conflict resolution in progress will be discarded.", actionTitle: "Abort") { [self] in
            perform("Aborting…", success: "Aborted") {
                switch state {
                case .merging: try await self.git.abortMerge()
                case .rebasing: try await self.git.abortRebase()
                case .cherryPicking: try await self.git.abortCherryPick()
                case .reverting: try await self.git.abortRevert()
                case .normal: break
                }
            }
        }
    }

    func continueRebase() {
        perform("Continuing rebase…", success: "Rebase continued") { try await self.git.continueRebase() }
    }

    // MARK: - Sidebar

    private func sidebarChanged() {
        switch sidebarSelection {
        case .branch(let name):
            if let b = localBranches.first(where: { $0.name == name }) { jump(to: b.hash) }
        case .remoteBranch(let name):
            if let b = remoteBranches.first(where: { $0.name == name }) { jump(to: b.hash) }
        case .tag(let name):
            if let t = tags.first(where: { $0.name == name }) { jump(to: t.hash) }
        case .stash(let ref):
            if let s = stashes.first(where: { $0.ref == ref }) { selectCommit(s.hash) }
        default:
            break
        }
    }

    var showsHistory: Bool {
        switch sidebarSelection {
        case .fileStatus, .stash: return false
        default: return true
        }
    }

    func jump(to hash: String) {
        selectCommit(hash)
        scrollToken += 1
        scrollRequest = (hash, scrollToken)
    }

    // MARK: - Commit details

    func selectCommit(_ id: String?) {
        guard id != selectedCommitID || commitDetail == nil else { return }
        selectedCommitID = id
        loadCommitDetail()
    }

    /// Parents of a loaded commit, so details and file list can be fetched in parallel.
    func parents(of id: String) -> [String]? {
        rowIndex[id].map { rows[$0].commit.parents }
    }

    func loadCommitDetail() {
        detailGeneration += 1
        let gen = detailGeneration
        guard let id = selectedCommitID else {
            commitDetail = nil; commitDiff = nil; selectedCommitFile = nil
            return
        }
        if id == workingCopyID {
            var seen = Set<String>()
            var files: [FileChange] = []
            for f in status.staged + status.unstaged where seen.insert(f.path).inserted {
                files.append(FileChange(path: f.path, originalPath: f.originalPath, kind: f.kind, staged: false))
            }
            let keep = selectedCommitFile.flatMap { sel in files.first { $0.path == sel.path } }
            commitDetail = CommitDetail(hash: workingCopyID, parents: status.headOID.map { [$0] } ?? [], author: "", authorEmail: "",
                                        authorDate: Date(), committer: "", committerEmail: "",
                                        message: "Uncommitted changes", files: files)
            selectCommitFile(keep ?? files.first)
            return
        }
        let knownParents = parents(of: id)
        Task {
            // Holding an arrow key fires many selections; only load the one the user stops on.
            try? await Task.sleep(nanoseconds: 25_000_000)
            guard gen == detailGeneration else { return }
            let detail = await git.commitDetail(id, knownParents: knownParents)
            guard gen == detailGeneration else { return }
            commitDetail = detail
            let keepPath = selectedCommitFile?.path
            let file = detail?.files.first { $0.path == keepPath } ?? detail?.files.first
            selectCommitFile(file)
        }
    }

    func selectCommitFile(_ file: FileChange?) {
        selectedCommitFile = file
        detailGeneration += 1
        let gen = detailGeneration
        guard let file, let detail = commitDetail else { commitDiff = nil; return }
        commitDiffLoading = true
        Task {
            let diff: FileDiff
            if detail.hash == workingCopyID {
                diff = await headDiff(file)
            } else {
                diff = await git.commitDiff(detail.hash, parents: detail.parents, file: file)
            }
            guard gen == detailGeneration else { return }
            commitDiff = diff
            commitDiffLoading = false
        }
    }

    private func headDiff(_ file: FileChange) async -> FileDiff {
        if file.kind == .untracked { return await git.workingDiff(file) }
        let r = await GitRunner.run(["diff", "--no-ext-diff", "-M", "HEAD", "--", file.path], in: root)
        return Parsers.parseDiff(r.output)
    }

    // MARK: - File status

    func selectStatusFile(_ file: FileChange?) {
        selectedStatusFile = file
        loadStatusDiff()
    }

    func loadStatusDiff() {
        statusDiffGeneration += 1
        let gen = statusDiffGeneration
        guard let file = selectedStatusFile else { statusDiff = nil; return }
        Task {
            let diff = await git.workingDiff(file)
            guard gen == statusDiffGeneration else { return }
            statusDiff = diff
        }
    }

    func stage(_ files: [FileChange]) {
        applyOptimistic(staging: true, files)
        let paths = files.flatMap { f in [f.path] + (f.originalPath.map { [$0] } ?? []) }
        perform("Staging…", refresh: false) {
            try await self.git.stage(paths)
            await self.refreshStatus()
        }
        if let sel = selectedStatusFile, files.contains(where: { $0.path == sel.path }) {
            selectedStatusFile = FileChange(path: sel.path, originalPath: sel.originalPath, kind: sel.kind == .untracked ? .added : sel.kind, staged: true)
        }
    }

    func unstage(_ files: [FileChange]) {
        applyOptimistic(staging: false, files)
        let paths = files.flatMap { f in [f.path] + (f.originalPath.map { [$0] } ?? []) }
        perform("Unstaging…", refresh: false) {
            try await self.git.unstage(paths)
            await self.refreshStatus()
        }
        if let sel = selectedStatusFile, files.contains(where: { $0.path == sel.path }) {
            selectedStatusFile = FileChange(path: sel.path, originalPath: nil, kind: sel.kind, staged: false)
        }
    }

    /// Moves files between the lists immediately; the real status follows a moment later.
    private func applyOptimistic(staging: Bool, _ files: [FileChange]) {
        let paths = Set(files.map(\.path))
        var s = status
        if staging {
            let moving = s.unstaged.filter { paths.contains($0.path) }
            s.unstaged.removeAll { paths.contains($0.path) }
            for f in moving where !s.staged.contains(where: { $0.path == f.path }) {
                s.staged.append(FileChange(path: f.path, originalPath: f.originalPath,
                                           kind: f.kind == .untracked ? .added : f.kind, staged: true))
            }
            s.staged.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        } else {
            let moving = s.staged.filter { paths.contains($0.path) }
            s.staged.removeAll { paths.contains($0.path) }
            for f in moving where !s.unstaged.contains(where: { $0.path == f.path }) {
                s.unstaged.append(FileChange(path: f.path, originalPath: nil,
                                             kind: f.kind == .added ? .untracked : f.kind, staged: false))
            }
            s.unstaged.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        status = s
    }

    func stageAll() {
        applyOptimistic(staging: true, status.unstaged)
        perform("Staging all…", refresh: false) {
            try await self.git.stageAll()
            await self.refreshStatus()
        }
    }

    func unstageAll() {
        applyOptimistic(staging: false, status.staged)
        perform("Unstaging all…", refresh: false) {
            try await self.git.unstageAll()
            await self.refreshStatus()
        }
    }

    func discard(_ files: [FileChange]) {
        guard !files.isEmpty else { return }
        let names = files.count == 1 ? "“\(files[0].fileName)”" : "\(files.count) files"
        confirm = ConfirmRequest(
            title: "Discard changes to \(names)?",
            message: "All local changes will be lost. Untracked files are moved to the Trash.",
            actionTitle: "Discard Changes"
        ) { [self] in
            perform("Discarding…", refresh: false) {
                try await self.git.discard(files)
                await self.refreshStatus()
            }
        }
    }

    enum HunkAction { case stage, unstage, discard, reverse }

    func hunkAction(_ action: HunkAction, hunk: DiffHunk, in diff: FileDiff) {
        let patch = diff.patch(for: hunk)
        let run: () -> Void = { [self] in
            perform("Applying hunk…", refresh: action == .reverse) {
                switch action {
                case .stage: try await self.git.applyPatch(patch, cached: true, reverse: false)
                case .unstage: try await self.git.applyPatch(patch, cached: true, reverse: true)
                case .discard, .reverse: try await self.git.applyPatch(patch, cached: false, reverse: true)
                }
                if action != .reverse { await self.refreshStatus() }
            }
        }
        switch action {
        case .discard:
            confirm = ConfirmRequest(title: "Discard this hunk?", message: "The changes in this hunk will be lost.", actionTitle: "Discard Hunk", action: run)
        case .reverse:
            confirm = ConfirmRequest(title: "Reverse this hunk?", message: "The hunk is reversed in your working copy.", actionTitle: "Reverse Hunk", destructive: false, action: run)
        default:
            run()
        }
    }

    // MARK: - Commit

    func requestCommit() {
        sidebarSelection = .fileStatus
        commitFocusToken += 1
    }

    private func amendChanged(_ old: Bool) {
        guard amend != old else { return }
        if amend {
            savedMessageBeforeAmend = commitMessage
            Task {
                let last = await git.lastCommitMessage()
                if self.amend, self.commitMessage.isEmpty || self.commitMessage == self.savedMessageBeforeAmend { self.commitMessage = last }
            }
        } else {
            commitMessage = savedMessageBeforeAmend
        }
    }

    var canCommit: Bool {
        let hasMessage = !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasMessage && (!status.staged.isEmpty || amend || repoState == .merging)
    }

    func commit() {
        guard canCommit, !pushAfterCommit || currentBranch != nil else { return }
        let message = commitMessage
        let amend = self.amend
        let push = pushAfterCommit
        let branch = currentBranch
        let upstream = currentBranchInfo?.upstream
        perform(amend ? "Amending…" : "Committing…", success: push ? nil : "Committed") {
            try await self.git.commit(message: message, amend: amend)
            await MainActor.run {
                self.savedMessageBeforeAmend = ""
                self.commitMessage = ""
                self.amend = false
            }
            if push, let branch {
                let (remote, remoteBranch) = Self.splitUpstream(upstream) ?? (self.remotes.first ?? "origin", branch)
                await MainActor.run { self.activity = "Pushing…" }
                try await self.git.push(remote: remote, specs: [.init(local: branch, remote: remoteBranch)],
                                        setUpstream: upstream == nil, tags: false, force: amend)
                await MainActor.run { self.showToast("Committed and pushed to \(remote)/\(remoteBranch)") }
            }
        }
    }

    // MARK: - AI commit message

    private var aiTask: Task<Void, Never>?

    func generateCommitMessage() {
        guard !aiGenerating else { return }
        aiGenerating = true
        let draft = commitMessage
        let amend = self.amend
        let root = self.root
        aiTask = Task {
            defer { self.aiGenerating = false; self.aiTask = nil }
            do {
                let message = try await AICommitGenerator.generate(root: root, draft: draft, amend: amend)
                guard !Task.isCancelled else { return }
                self.commitMessage = message
                self.commitFocusToken += 1
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.problem = ProblemReport(symbol: "sparkles", title: "Couldn't generate a commit message",
                                             message: error.localizedDescription.components(separatedBy: "\n").first ?? "",
                                             hint: "Check Settings → AI, or try another model.",
                                             details: error.localizedDescription)
            }
        }
    }

    private var prepareTask: Task<Void, Never>?

    /// Quietly generates a message for the current staged changes so "Generate" is instant.
    /// Results are cached per staged state; nothing is filled in until the user asks.
    private func prepareCommitMessageSoon() {
        prepareTask?.cancel()
        guard AISettings.currentProvider != .off, AISettings.prepareInBackground,
              !status.staged.isEmpty, !amend else { return }
        let root = self.root
        prepareTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)   // wait until staging settles
            guard !Task.isCancelled, self.commitMessage.isEmpty else { return }
            _ = try? await AICommitGenerator.generate(root: root, draft: "", amend: false)
        }
    }

    func cancelCommitMessageGeneration() {
        aiTask?.cancel()
        aiTask = nil
        aiGenerating = false
    }

    static func splitUpstream(_ upstream: String?) -> (String, String)? {
        guard let upstream, let slash = upstream.firstIndex(of: "/") else { return nil }
        return (String(upstream[..<slash]), String(upstream[upstream.index(after: slash)...]))
    }

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
        if let up = RepoModel.splitUpstream(currentBranchInfo?.upstream), remotes.contains(up.0) { return up.0 }
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
