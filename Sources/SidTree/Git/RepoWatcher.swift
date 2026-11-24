import CoreServices
import Foundation

/// Watches a repository with FSEvents and reports whether refs (history) or only the working copy changed.
final class RepoWatcher {
    struct Change: OptionSet {
        let rawValue: Int
        static let workingCopy = Change(rawValue: 1)
        static let refs = Change(rawValue: 2)
        static let ignoreRules = Change(rawValue: 4)
    }

    /// Ignored directories ("var/cache/") and files, relative to the root. Events inside them are dropped,
    /// so build tools and caches writing thousands of files never trigger a status refresh.
    private var ignoredDirs = Set<String>()
    private var ignoredFiles = Set<String>()

    func setIgnored(_ paths: Set<String>) {
        var dirs = Set<String>(), files = Set<String>()
        for p in paths {
            if p.hasSuffix("/") { dirs.insert(String(p.dropLast())) } else { files.insert(p) }
        }
        ignoredDirs = dirs
        ignoredFiles = files
    }

    private func isIgnored(_ rel: String) -> Bool {
        if ignoredFiles.contains(rel) || ignoredDirs.contains(rel) { return true }
        guard !ignoredDirs.isEmpty else { return false }
        var idx = rel.startIndex
        while let slash = rel[idx...].firstIndex(of: "/") {
            if ignoredDirs.contains(String(rel[..<slash])) { return true }
            idx = rel.index(after: slash)
        }
        return false
    }

    private var stream: FSEventStreamRef?
    private let root: String
    private let gitDir: String
    private let handler: (Change) -> Void

    init(root: URL, gitDir: URL, handler: @escaping (Change) -> Void) {
        self.root = root.path
        self.gitDir = gitDir.path
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        var paths = [root]
        if !gitDir.hasPrefix(root + "/") { paths.append(gitDir) }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            watcher.process(Array(paths.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25, flags) else { return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func process(_ paths: [String]) {
        var change: Change = []
        let gitPrefix = gitDir + "/"
        let rootPrefix = root + "/"
        for p in paths {
            if p.hasPrefix(gitPrefix) || p == gitDir {
                let rel = String(p.dropFirst(min(p.count, gitPrefix.count)))
                if rel.hasPrefix("objects") || rel.hasSuffix(".lock") { continue }
                if rel == "info/exclude" { change.insert(.ignoreRules) }
                if rel == "index" {
                    change.insert(.workingCopy)
                } else if rel.hasPrefix("refs") || rel == "HEAD" || rel == "packed-refs" || rel == "FETCH_HEAD"
                            || rel == "ORIG_HEAD" || rel == "MERGE_HEAD" || rel.hasPrefix("rebase-") {
                    change.insert(.refs)
                    change.insert(.workingCopy)
                }
            } else {
                // Skip editor swap/temp noise.
                if p.hasSuffix(".swp") || p.hasSuffix("~") || p.hasSuffix("/.DS_Store") { continue }
                guard p.hasPrefix(rootPrefix) else { change.insert(.workingCopy); continue }
                let rel = String(p.dropFirst(rootPrefix.count))
                if rel.hasSuffix(".gitignore") || rel == ".git/info/exclude" { change.insert(.ignoreRules) }
                if isIgnored(rel) { continue }
                change.insert(.workingCopy)
            }
        }
        if !change.isEmpty { handler(change) }
    }
}
