import Foundation

let workingCopyID = "WORKING-COPY"

struct RefLabel: Hashable {
    enum Kind: Int { case head, localBranch, remoteBranch, tag }
    let name: String
    let kind: Kind
    var isCurrent = false
}

struct Commit: Identifiable, Hashable {
    let id: String
    let parents: [String]
    let author: String
    let email: String
    let date: Date
    let subject: String
    var refs: [RefLabel]

    var shortHash: String { String(id.prefix(8)) }
    var isWorkingCopy: Bool { id == workingCopyID }
    var isMerge: Bool { parents.count > 1 }
}

struct Branch: Identifiable, Hashable {
    var id: String { fullRef }
    let fullRef: String
    let name: String          // short name, e.g. "develop" or "origin/develop"
    let hash: String
    let isRemote: Bool
    let upstream: String?
    let ahead: Int
    let behind: Int
    let upstreamGone: Bool
    let isHead: Bool

    var remoteName: String? {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return nil }
        return String(name[..<slash])
    }

    /// Branch name without the remote prefix.
    var shortName: String {
        guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

struct Tag: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let hash: String
}

struct Stash: Identifiable, Hashable {
    var id: String { ref }
    let ref: String     // stash@{0}
    let hash: String
    let date: Date
    let message: String
}

enum FileStatusKind: String {
    case modified = "M", added = "A", deleted = "D", renamed = "R", copied = "C"
    case typeChanged = "T", untracked = "?", conflicted = "U", unknown = "X"
}

struct FileChange: Identifiable, Hashable {
    var id: String { (staged ? "S:" : "W:") + path }
    let path: String
    let originalPath: String?
    let kind: FileStatusKind
    let staged: Bool

    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

/// Added and removed line counts of one file; nil for binary files.
struct LineStat: Equatable {
    let added: Int?
    let removed: Int?
}

enum RepoState: Equatable {
    case normal, merging, rebasing, cherryPicking, reverting
}

struct StatusSnapshot: Equatable {
    var branch: String?       // nil when detached
    var headOID: String?      // nil for unborn branch
    var upstream: String?
    var ahead = 0
    var behind = 0
    var staged: [FileChange] = []
    var unstaged: [FileChange] = []
    var conflicted: Set<String> = []
}

struct CommitDetail: Equatable {
    let hash: String
    let parents: [String]
    let author: String
    let authorEmail: String
    let authorDate: Date
    let committer: String
    let committerEmail: String
    let message: String
    var files: [FileChange]

    var subject: String { message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "" }
    var body: String {
        let parts = message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

// MARK: - Diff

enum DiffLineKind { case context, added, removed, noNewline }

struct DiffLine: Identifiable {
    let id: Int
    let kind: DiffLineKind
    let text: String
    let oldLine: Int?
    let newLine: Int?
    let raw: String
}

struct DiffHunk: Identifiable {
    let id: Int
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    var lines: [DiffLine]
}

/// Before/after contents of a changed image, shown instead of "binary file".
struct ImageComparison {
    let id = UUID()
    /// nil when the image did not exist before (added) …
    var old: Data?
    /// … or no longer exists (deleted).
    var new: Data?

    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif", "ico", "icns", "avif"]
    /// Larger files are not previewed.
    static let maxBytes = 40_000_000

    static func isImage(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }
}

struct FileDiff {
    var images: ImageComparison?
    var headerLines: [String] = []
    var hunks: [DiffHunk] = []
    var isBinary = false
    var tooLarge = false
    var maxLineLength = 0
    var added = 0
    var removed = 0
    var lineCount: Int { hunks.reduce(0) { $0 + $1.lines.count } }

    /// A patch containing only one hunk, suitable for `git apply`.
    func patch(for hunk: DiffHunk) -> String {
        var out = headerLines.joined(separator: "\n") + "\n"
        out += hunk.header + "\n"
        for line in hunk.lines { out += line.raw + "\n" }
        return out
    }
}

enum DiffContext: Equatable {
    case unstaged, staged, commit, readOnly
}
