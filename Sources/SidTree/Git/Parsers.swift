import Foundation

enum Parsers {
    static let fieldSep: Character = "\u{1F}"

    // MARK: Log

    /// Byte-level parser for `git log -z --format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s`.
    /// Avoids intermediate String splitting; ~4x faster than a String-based parser.
    static func parseLog(_ data: Data) -> [Commit] {
        var commits: [Commit] = []
        commits.reserveCapacity(max(16, data.count / 160))
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let p = raw.bindMemory(to: UInt8.self)
            let n = p.count
            var starts = [Int](repeating: 0, count: 7)
            var ends = [Int](repeating: 0, count: 7)
            var authorCache: [String: String] = [:]

            @inline(__always) func str(_ a: Int, _ b: Int) -> String {
                a >= b ? "" : String(decoding: UnsafeBufferPointer(rebasing: p[a..<b]), as: UTF8.self)
            }

            var i = 0
            while i < n {
                while i < n && (p[i] == 0x0A || p[i] == 0) { i += 1 }
                guard i < n else { break }
                var field = 0
                starts[0] = i
                var j = i
                while j < n && p[j] != 0 {
                    if p[j] == 0x1F && field < 6 {
                        ends[field] = j
                        field += 1
                        starts[field] = j + 1
                    }
                    j += 1
                }
                ends[field] = j
                defer { i = j + 1 }
                guard field == 6 else { continue }

                // Parents: space separated hashes.
                var parents: [String] = []
                var ps = starts[1]
                var k = starts[1]
                while k <= ends[1] {
                    if k == ends[1] || p[k] == 0x20 {
                        if k > ps { parents.append(str(ps, k)) }
                        ps = k + 1
                    }
                    k += 1
                }

                var ts = 0
                for x in starts[4]..<ends[4] {
                    let d = Int(p[x]) - 48
                    if d >= 0 && d <= 9 { ts = ts * 10 + d }
                }

                // Authors repeat a lot; intern them to save memory.
                var author = str(starts[2], ends[2])
                if let cached = authorCache[author] { author = cached } else { authorCache[author] = author }
                var email = str(starts[3], ends[3])
                if let cached = authorCache[email] { email = cached } else { authorCache[email] = email }

                commits.append(Commit(
                    id: str(starts[0], ends[0]),
                    parents: parents,
                    author: author,
                    email: email,
                    date: Date(timeIntervalSince1970: TimeInterval(ts)),
                    subject: str(starts[6], ends[6]),
                    refs: ends[5] > starts[5] ? parseDecorations(str(starts[5], ends[5])) : []
                ))
            }
        }
        return commits
    }

    /// Parses `%D` output produced with `--decorate=full`.
    static func parseDecorations(_ s: String) -> [RefLabel] {
        guard !s.isEmpty else { return [] }
        var labels: [RefLabel] = []
        var currentBranch: String?
        for rawPart in s.components(separatedBy: ", ") {
            var part = rawPart.trimmingCharacters(in: .whitespaces)
            if part == "HEAD" {
                labels.append(RefLabel(name: "HEAD", kind: .head, isCurrent: true))
                continue
            }
            if part.hasPrefix("HEAD -> ") {
                part = String(part.dropFirst("HEAD -> ".count))
                if part.hasPrefix("refs/heads/") { currentBranch = String(part.dropFirst("refs/heads/".count)) }
            }
            if part.hasPrefix("tag: ") { part = String(part.dropFirst(5)) }
            if part.hasPrefix("refs/heads/") {
                let name = String(part.dropFirst("refs/heads/".count))
                labels.append(RefLabel(name: name, kind: .localBranch, isCurrent: name == currentBranch))
            } else if part.hasPrefix("refs/remotes/") {
                labels.append(RefLabel(name: String(part.dropFirst("refs/remotes/".count)), kind: .remoteBranch))
            } else if part.hasPrefix("refs/tags/") {
                labels.append(RefLabel(name: String(part.dropFirst("refs/tags/".count)), kind: .tag))
            }
        }
        // Current branch first, then local, remote, tags.
        return labels.sorted { a, b in
            if a.isCurrent != b.isCurrent { return a.isCurrent }
            return a.kind.rawValue < b.kind.rawValue
        }
    }

    // MARK: Refs

    struct RefsResult {
        var local: [Branch] = []
        var remote: [Branch] = []
        var tags: [Tag] = []
    }

    static func parseRefs(_ text: String) -> RefsResult {
        var result = RefsResult()
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6 else { continue }
            let full = f[0], hash = f[1], upstream = f[2], track = f[3], head = f[4], peeled = f[5]
            if full.hasPrefix("refs/heads/") {
                let (ahead, behind, gone) = parseTrack(track)
                result.local.append(Branch(
                    fullRef: full, name: String(full.dropFirst(11)), hash: hash, isRemote: false,
                    upstream: upstream.isEmpty ? nil : upstream, ahead: ahead, behind: behind,
                    upstreamGone: gone, isHead: head == "*"))
            } else if full.hasPrefix("refs/remotes/") {
                let name = String(full.dropFirst(13))
                if name.hasSuffix("/HEAD") { continue }
                result.remote.append(Branch(
                    fullRef: full, name: name, hash: hash, isRemote: true, upstream: nil,
                    ahead: 0, behind: 0, upstreamGone: false, isHead: false))
            } else if full.hasPrefix("refs/tags/") {
                result.tags.append(Tag(name: String(full.dropFirst(10)), hash: peeled.isEmpty ? hash : peeled))
            }
        }
        let byName: (Branch, Branch) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        result.local.sort(by: byName)
        result.remote.sort(by: byName)
        result.tags.sort { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        return result
    }

    static func parseTrack(_ s: String) -> (Int, Int, Bool) {
        if s == "gone" { return (0, 0, true) }
        var ahead = 0, behind = 0
        for part in s.components(separatedBy: ", ") {
            let p = part.split(separator: " ")
            guard p.count == 2, let n = Int(p[1]) else { continue }
            if p[0] == "ahead" { ahead = n } else if p[0] == "behind" { behind = n }
        }
        return (ahead, behind, false)
    }

    // MARK: Status (porcelain v2, -z)

    static func parseStatus(_ data: Data) -> StatusSnapshot {
        var snap = StatusSnapshot()
        let tokens = splitNul(data)
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            i += 1
            guard let first = t.first else { continue }
            switch first {
            case "#":
                let parts = t.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 3 else { continue }
                switch parts[1] {
                case "branch.oid": snap.headOID = parts[2] == "(initial)" ? nil : parts[2]
                case "branch.head": snap.branch = parts[2] == "(detached)" ? nil : parts[2]
                case "branch.upstream": snap.upstream = parts[2]
                case "branch.ab":
                    for v in parts[2].split(separator: " ") {
                        if v.hasPrefix("+") { snap.ahead = Int(v.dropFirst()) ?? 0 }
                        if v.hasPrefix("-") { snap.behind = Int(v.dropFirst()) ?? 0 }
                    }
                default: break
                }
            case "1", "2":
                let fieldCount = first == "1" ? 8 : 9
                let parts = t.split(separator: " ", maxSplits: fieldCount, omittingEmptySubsequences: false)
                guard parts.count == fieldCount + 1 else { continue }
                let xy = Array(parts[1])
                let path = String(parts[fieldCount])
                var orig: String?
                if first == "2", i < tokens.count { orig = tokens[i]; i += 1 }
                if xy[0] != "." {
                    snap.staged.append(FileChange(path: path, originalPath: orig, kind: kind(xy[0]), staged: true))
                }
                if xy[1] != "." {
                    snap.unstaged.append(FileChange(path: path, originalPath: nil, kind: kind(xy[1]), staged: false))
                }
            case "u":
                let parts = t.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard parts.count == 11 else { continue }
                let path = String(parts[10])
                snap.conflicted.insert(path)
                snap.unstaged.append(FileChange(path: path, originalPath: nil, kind: .conflicted, staged: false))
            case "?":
                let path = String(t.dropFirst(2))
                snap.unstaged.append(FileChange(path: path, originalPath: nil, kind: .untracked, staged: false))
            default:
                break
            }
        }
        let byPath: (FileChange, FileChange) -> Bool = { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        snap.staged.sort(by: byPath)
        snap.unstaged.sort(by: byPath)
        return snap
    }

    static func kind(_ c: Character) -> FileStatusKind {
        FileStatusKind(rawValue: String(c)) ?? .modified
    }

    // MARK: name-status -z

    static func parseNameStatus(_ data: Data) -> [FileChange] {
        let tokens = splitNul(data)
        var files: [FileChange] = []
        var i = 0
        while i < tokens.count {
            let status = tokens[i]
            i += 1
            guard let c = status.first else { continue }
            if c == "R" || c == "C" {
                guard i + 1 < tokens.count else { break }
                files.append(FileChange(path: tokens[i + 1], originalPath: tokens[i], kind: kind(c), staged: false))
                i += 2
            } else {
                guard i < tokens.count else { break }
                files.append(FileChange(path: tokens[i], originalPath: nil, kind: kind(c), staged: false))
                i += 1
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: numstat -z

    /// `--numstat -z`: "added\tremoved\tpath\0", or "added\tremoved\t\0old\0new\0" for renames. Binary files use "-".
    static func parseNumstat(_ data: Data) -> [String: LineStat] {
        let tokens = splitNul(data)
        var stats: [String: LineStat] = [:]
        var i = 0
        while i < tokens.count {
            let parts = tokens[i].split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            i += 1
            guard parts.count == 3 else { continue }
            let stat = LineStat(added: Int(parts[0]), removed: Int(parts[1]))
            if parts[2].isEmpty {
                guard i + 1 < tokens.count else { break }
                stats[tokens[i + 1]] = stat
                i += 2
            } else {
                stats[String(parts[2])] = stat
            }
        }
        return stats
    }

    // MARK: Stash

    static func parseStashes(_ data: Data) -> [Stash] {
        splitNul(data).compactMap { record in
            let f = record.split(separator: fieldSep, maxSplits: 3, omittingEmptySubsequences: false)
            guard f.count == 4 else { return nil }
            return Stash(ref: String(f[0]).trimmingCharacters(in: .whitespacesAndNewlines), hash: String(f[1]),
                         date: Date(timeIntervalSince1970: TimeInterval(f[2]) ?? 0), message: String(f[3]))
        }
    }

    // MARK: Diff

    static func parseDiff(_ text: String) -> FileDiff {
        var diff = FileDiff()
        var current: DiffHunk?
        var oldNo = 0, newNo = 0
        var lineID = 0
        var hunkID = 0
        var maxLen = 0

        func flush() {
            if let h = current { diff.hunks.append(h) }
            current = nil
        }

        for sub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(sub)
            if line.hasPrefix("@@") {
                flush()
                let (os, oc, ns, nc) = parseHunkHeader(line)
                oldNo = os; newNo = ns
                current = DiffHunk(id: hunkID, header: line, oldStart: os, oldCount: oc, newStart: ns, newCount: nc, lines: [])
                hunkID += 1
                continue
            }
            if current == nil {
                if line.hasPrefix("Binary files") || line.hasPrefix("GIT binary patch") { diff.isBinary = true }
                if !line.isEmpty { diff.headerLines.append(line) }
                continue
            }
            if line.hasPrefix("diff --git") {
                // A second file section; stop – we only ever diff one file at a time.
                break
            }
            guard let first = line.first else { continue }
            let body = String(line.dropFirst())
            let display = body.replacingOccurrences(of: "\t", with: "    ")
            maxLen = max(maxLen, display.count)
            switch first {
            case "+":
                current?.lines.append(DiffLine(id: lineID, kind: .added, text: display, oldLine: nil, newLine: newNo, raw: line))
                newNo += 1
                diff.added += 1
            case "-":
                current?.lines.append(DiffLine(id: lineID, kind: .removed, text: display, oldLine: oldNo, newLine: nil, raw: line))
                oldNo += 1
                diff.removed += 1
            case "\\":
                current?.lines.append(DiffLine(id: lineID, kind: .noNewline, text: line, oldLine: nil, newLine: nil, raw: line))
            default:
                current?.lines.append(DiffLine(id: lineID, kind: .context, text: display, oldLine: oldNo, newLine: newNo, raw: line))
                oldNo += 1; newNo += 1
            }
            lineID += 1
        }
        flush()
        diff.maxLineLength = maxLen
        return diff
    }

    static func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int) {
        // @@ -a,b +c,d @@ context
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { return (0, 0, 0, 0) }
        func nums(_ s: Substring) -> (Int, Int) {
            let comps = s.dropFirst().split(separator: ",")
            let start = Int(comps.first ?? "0") ?? 0
            let count = comps.count > 1 ? Int(comps[1]) ?? 1 : 1
            return (start, count)
        }
        let (os, oc) = nums(parts[1])
        let (ns, nc) = nums(parts[2])
        return (os, oc, ns, nc)
    }

    // MARK: Helpers

    static func splitNul(_ data: Data) -> [String] {
        var result: [String] = []
        var start = data.startIndex
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let base = data.startIndex
            for (offset, byte) in buf.enumerated() where byte == 0 {
                let idx = base + offset
                result.append(String(decoding: data[start..<idx], as: UTF8.self))
                start = idx + 1
            }
        }
        if start < data.endIndex {
            let tail = String(decoding: data[start..<data.endIndex], as: UTF8.self)
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(tail) }
        }
        // Records after the first in `git log -z` start with a newline in some formats; strip it.
        return result.map { $0.hasPrefix("\n") ? String($0.dropFirst()) : $0 }
    }
}
