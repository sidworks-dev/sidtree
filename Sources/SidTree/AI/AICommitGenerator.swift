import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case off, claude, codex
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var executable: String? {
        switch self {
        case .off: return nil
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case haiku, sonnet, opus
    var id: String { rawValue }
    var title: String {
        switch self {
        case .haiku: return "Haiku — fastest, cheapest (recommended)"
        case .sonnet: return "Sonnet — balanced"
        case .opus: return "Opus — most capable, slow"
        }
    }
}

/// Settings keys (also used with @AppStorage).
enum AISettings {
    static let provider = "ai.provider"
    static let claudeModel = "ai.claudeModel"
    static let codexModel = "ai.codexModel"
    static let codexEffort = "ai.codexEffort"
    static let instruction = "ai.instruction"
    static let maxDiff = "ai.maxDiff"
    static let singleLine = "ai.singleLine"
    static let prepare = "ai.prepareInBackground"

    static var isSingleLine: Bool { UserDefaults.standard.object(forKey: singleLine) as? Bool ?? true }
    static var prepareInBackground: Bool { UserDefaults.standard.object(forKey: prepare) as? Bool ?? true }
    static let claudeCustom = "ai.claudeCustom"
    static let codexCustom = "ai.codexCustom"

    static let customModelTag = "__custom__"

    static let defaultInstruction = """
    Write a one-line git commit message for the staged changes.
    - Imperative mood, max 72 characters, no trailing period.
    - Say concretely what changed. Do not invent details. Never mention AI.
    - Example: Strip template inspector markers from HTML fragments
    Reply with only the commit message.
    """

    static var currentProvider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: provider) ?? "") ?? .off
    }

    static var currentInstruction: String {
        let v = (UserDefaults.standard.string(forKey: instruction) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultInstruction : v
    }

    static var currentMaxDiff: Int {
        let v = UserDefaults.standard.integer(forKey: maxDiff)
        return v > 0 ? v : 12_000
    }

    static var currentClaudeModel: String {
        let d = UserDefaults.standard
        var v = (d.string(forKey: claudeModel) ?? "").trimmingCharacters(in: .whitespaces)
        if v == customModelTag { v = (d.string(forKey: claudeCustom) ?? "").trimmingCharacters(in: .whitespaces) }
        return v.isEmpty ? ClaudeModel.haiku.rawValue : v
    }

    /// Codex models offered by the user's Codex install (read from its local model cache).
    static func codexModels() -> [(slug: String, name: String)] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { m in
            guard let slug = m["slug"] as? String, (m["visibility"] as? String ?? "list") == "list" else { return nil }
            return (slug, m["display_name"] as? String ?? slug)
        }
    }

    /// Prefer a small/fast model ("mini", "luna", "nano") when the user did not choose one.
    static var currentCodexModel: String? {
        let d = UserDefaults.standard
        var v = (d.string(forKey: codexModel) ?? "").trimmingCharacters(in: .whitespaces)
        if v == customModelTag { v = (d.string(forKey: codexCustom) ?? "").trimmingCharacters(in: .whitespaces) }
        if !v.isEmpty { return v }
        return autoCodexModel
    }

    static var autoCodexModel: String? {
        let models = codexModels().map(\.slug)
        for hint in ["mini", "nano", "luna", "flash"] {
            if let m = models.first(where: { $0.localizedCaseInsensitiveContains(hint) }) { return m }
        }
        return models.first
    }

    static var currentCodexEffort: String {
        let v = UserDefaults.standard.string(forKey: codexEffort) ?? ""
        return v.isEmpty ? "low" : v
    }
}

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Generates commit messages with the user's locally installed `claude` or `codex` CLI,
/// using their own login. Nothing is sent anywhere unless the user enabled a provider.
enum AICommitGenerator {

    // MARK: Locating the CLI

    /// PATH from the user's login shell; apps started from Finder only get a minimal PATH,
    /// which misses nvm / bun / ~/.local/bin installs.
    private static let loginShellPath: String = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let out = try? runSync(shell, ["-l", "-c", "env"], cwd: nil, env: ProcessInfo.processInfo.environment,
                                     stdin: nil, timeout: 5).stdout else { return "" }
        for line in out.split(separator: "\n") where line.hasPrefix("PATH=") {
            return String(line.dropFirst(5))
        }
        return ""
    }()

    static let searchPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var parts: [String] = []
        for p in loginShellPath.split(separator: ":").map(String.init)
            + (GitRunner.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.bun/bin", "\(home)/.volta/bin",
               "\(home)/.npm-global/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        where !p.isEmpty && !parts.contains(p) {
            parts.append(p)
        }
        return parts.joined(separator: ":")
    }()

    private static var locateCache: [String: String?] = [:]
    private static let cacheLock = NSLock()

    static func locate(_ provider: AIProvider) async -> String? {
        guard let name = provider.executable else { return nil }
        if let cached = cacheLock.withLock({ locateCache[name] }) { return cached }
        let found: String? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                let hit = searchPath.split(separator: ":")
                    .map { "\($0)/\(name)" }
                    .first { fm.isExecutableFile(atPath: $0) }
                cont.resume(returning: hit)
            }
        }
        cacheLock.withLock { locateCache[name] = found }
        return found
    }

    // MARK: Generating

    // MARK: Cache

    /// Results per (settings + prompt). A background "prepare" fills it so Generate is instant.
    private actor ResultCache {
        var done: [String: String] = [:]
        var running: [String: Task<String, Error>] = [:]

        func value(for key: String, start: @escaping @Sendable () async throws -> String) async throws -> String {
            if let hit = done[key] { return hit }
            if let task = running[key] { return try await task.value }
            let task = Task { try await start() }
            running[key] = task
            defer { running[key] = nil }
            let result = try await task.value
            if done.count > 50 { done.removeAll() }
            done[key] = result
            return result
        }

        func cached(_ key: String) -> String? { done[key] }
    }

    private static let cache = ResultCache()

    /// Generates (or returns the prepared) commit message for the current staged changes.
    static func generate(root: URL, draft: String, amend: Bool) async throws -> String {
        let provider = AISettings.currentProvider
        guard provider != .off else { throw AIError(message: "AI commit messages are turned off in Settings.") }
        guard let exe = await locate(provider) else {
            throw AIError(message: "Could not find the `\(provider.executable ?? "")` command. Install it or pick another provider in Settings.")
        }
        let prompt = try await buildPrompt(root: root, draft: draft, amend: amend)
        let instruction = AISettings.currentInstruction
        let model = provider == .claude ? AISettings.currentClaudeModel : (AISettings.currentCodexModel ?? "")
        let key = [provider.rawValue, model, AISettings.currentCodexEffort, instruction,
                   String(AISettings.isSingleLine), prompt].joined(separator: "\u{1}")
        return try await cache.value(for: key) {
            try await requestValidMessage(provider: provider, exe: exe, prompt: prompt, instruction: instruction)
        }
    }

    /// Asks once more with a stricter prompt when the model answers with prose instead of a commit message.
    private static func requestValidMessage(provider: AIProvider, exe: String, prompt: String, instruction: String) async throws -> String {
        var lastOutput = ""
        for attempt in 0..<2 {
            let p = attempt == 0 ? prompt : """
            Your previous reply was not a commit message. Do NOT review, explain, ask questions or mention the workspace. \
            Everything you need is below. Reply with the commit message only.

            \(prompt)
            """
            let raw = try await request(provider: provider, exe: exe, prompt: p, instruction: instruction)
            var message = clean(raw)
            if AISettings.isSingleLine {
                message = message.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                while message.hasSuffix(".") { message.removeLast() }
            }
            if looksLikeCommitMessage(message) { return message }
            lastOutput = raw
        }
        let preview = lastOutput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)
        throw AIError(message: "\(provider.title) did not return a usable commit message. Nothing was changed.\n\nReply was:\n\(preview)")
    }

    /// Rejects answers that read like a review, a question or an explanation.
    static func looksLikeCommitMessage(_ message: String) -> Bool {
        guard let first = message.split(separator: "\n").first.map(String.init), !first.isEmpty else { return false }
        if first.count > 100 || first.hasSuffix("?") || first.hasSuffix(":") { return false }
        let lower = message.lowercased()
        let prose = ["i couldn", "i could not", "i can't", "i cannot", "i can’t", "i'm unable", "i am unable",
                     "workspace", "would you like", "from the diff", "this diff", "the diff ", "this change ",
                     "here is", "here's", "let me", "i'll ", "i will ", "as an ai", "git checkout"]
        if prose.contains(where: { lower.contains($0) }) { return false }
        // A body is fine, but long multi-paragraph essays are not.
        if message.split(separator: "\n").count > 12 { return false }
        return true
    }

    private static func request(provider: AIProvider, exe: String, prompt: String, instruction: String) async throws -> String {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        env["NO_COLOR"] = "1"

        // Run outside the repository: the full context is in the prompt, and this keeps
        // project hooks, CLAUDE.md files and agent sandboxes out of the way.
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("sidtree-ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        switch provider {
        case .claude:
            // Minimal request: own short system prompt, no tools, no MCP servers, no hooks/plugins.
            // ~800 tokens of overhead with Haiku, typically 2 seconds.
            let args = ["-p", "--output-format", "text",
                        "--model", AISettings.currentClaudeModel,
                        "--setting-sources", "",
                        "--tools", "",
                        "--strict-mcp-config",
                        "--no-session-persistence",
                        "--system-prompt", instruction]
            let r = try await run(exe, args, cwd: workDir, env: env, stdin: prompt, timeout: 120)
            guard r.status == 0 else { throw AIError(message: failure("Claude Code", r)) }
            return r.stdout
        case .codex:
            // Replace Codex's agent instructions, skip the user config (MCP servers, profiles) and switch
            // off every tool so it cannot wander off inspecting a workspace. `-c features.x=false` is used
            // instead of `--disable x` because unknown names are ignored rather than fatal.
            let outFile = workDir.appendingPathComponent("codex-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: outFile) }
            var args = ["exec", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config",
                        "--sandbox", "read-only", "--color", "never",
                        "-c", "model_reasoning_effort=\(tomlString(AISettings.currentCodexEffort))",
                        "-c", "base_instructions=\(tomlString(instruction))",
                        "-c", "web_search=\"disabled\""]
            for feature in ["shell_tool", "unified_exec", "apps", "plugins", "browser_use", "in_app_browser",
                            "computer_use", "multi_agent", "image_generation", "view_image", "hooks",
                            "skill_search", "tool_suggest", "sleep_tool", "goals"] {
                args += ["-c", "features.\(feature)=false"]
            }
            args += ["-o", outFile.path]
            if let model = AISettings.currentCodexModel { args += ["-m", model] }
            args.append("-")
            let codexPrompt = "Instructions:\n\(instruction)\n\n\(prompt)"
            let r = try await run(exe, args, cwd: workDir, env: env, stdin: codexPrompt, timeout: 180)
            guard r.status == 0 else { throw AIError(message: failure("Codex", r)) }
            return (try? String(contentsOf: outFile, encoding: .utf8)) ?? r.stdout
        case .off:
            return ""
        }
    }

    private static func tomlString(_ v: String) -> String {
        var out = "\""
        for ch in v.unicodeScalars {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += ""
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out + "\""
    }

    /// Compact context: numstat file list, recent subjects for style, and a trimmed diff
    /// (1 line of context, no index/---/+++ headers, per-file and total size caps).
    private static func buildPrompt(root: URL, draft: String, amend: Bool) async throws -> String {
        let excludes = [":(exclude)*.lock", ":(exclude)package-lock.json", ":(exclude)pnpm-lock.yaml", ":(exclude)yarn.lock",
                        ":(exclude)*.min.js", ":(exclude)*.min.css", ":(exclude)*.map", ":(exclude)*.svg"]
        async let numstatR = GitRunner.run(["diff", "--cached", "--numstat", "-M"], in: root)
        async let diffR = GitRunner.run(["diff", "--cached", "--no-ext-diff", "--no-color", "-U1", "-M", "--", "."] + excludes, in: root)
        async let logR = GitRunner.run(["log", "-5", "--format=%s"], in: root)
        async let branchR = GitRunner.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
        var (numstat, diff, log, branch) = await (numstatR.output, diffR.output, logR.output, branchR.output)

        if amend && numstat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Amending without new staged changes: describe the last commit itself.
            numstat = await GitRunner.run(["show", "--numstat", "--format=", "-M", "HEAD"], in: root).output
            diff = await GitRunner.run(["show", "--format=", "--no-ext-diff", "--no-color", "-U1", "-M", "HEAD", "--", "."] + excludes, in: root).output
        }
        guard !numstat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError(message: "Stage some changes first, then generate a message.")
        }

        let files = numstat.split(separator: "\n").map { line -> String in
            let p = line.split(separator: "\t", maxSplits: 2)
            guard p.count == 3 else { return String(line) }
            return p[0] == "-" ? "bin \(p[2])" : "+\(p[0]) -\(p[1]) \(p[2])"
        }

        var prompt = "Task: write the git commit message for the staged changes below. Follow the instructions exactly; "
            + "where they define a format, it overrides the style of the recent commits. Reply with only the commit message.\n\n"
        prompt += "Branch: \(branch.trimmingCharacters(in: .whitespacesAndNewlines))"
        if amend { prompt += " (amending the last commit)" }
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty { prompt += "\nUser's draft (keep its intent):\n\(trimmedDraft)" }
        prompt += "\nRecent commits (style reference only):\n\(log.trimmingCharacters(in: .newlines))"
        prompt += "\nFiles (\(files.count)):\n" + files.prefix(60).joined(separator: "\n")
        if files.count > 60 { prompt += "\n… \(files.count - 60) more" }
        prompt += "\nDiff:\n" + compactDiff(diff, total: AISettings.currentMaxDiff)
        return prompt
    }

    static func compactDiff(_ diff: String, total: Int, perFile: Int = 2_000) -> String {
        var out = ""
        var section = ""
        func flush() {
            guard !section.isEmpty else { return }
            if section.count > perFile {
                section = String(section.prefix(perFile)) + "\n[… file diff truncated]\n"
            }
            out += section
            section = ""
        }
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                flush()
                // "diff --git a/x b/x" -> "## x"
                let parts = line.split(separator: " ")
                let name = parts.last.map { $0.hasPrefix("b/") ? String($0.dropFirst(2)) : String($0) } ?? String(line)
                section = "## \(name)\n"
                continue
            }
            if line.hasPrefix("index ") || line.hasPrefix("--- ") || line.hasPrefix("+++ ")
                || line.hasPrefix("similarity index") || line.hasPrefix("new file mode") || line.hasPrefix("deleted file mode")
                || line.hasPrefix("old mode") || line.hasPrefix("new mode") { continue }
            section += line + "\n"
        }
        flush()
        if out.count > total {
            out = String(out.prefix(total)) + "\n[… diff truncated]"
        }
        return out
    }

    static func clean(_ raw: String) -> String {
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // Drop markdown fences and empty edges.
        lines.removeAll { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        for q in ["\"", "'", "`"] where text.hasPrefix(q) && text.hasSuffix(q) && text.count > 1 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Some models prefix with a label.
        for label in ["Commit message:", "commit message:"] where text.hasPrefix(label) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func failure(_ name: String, _ r: ProcessResult) -> String {
        let detail = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = detail.split(separator: "\n").suffix(8).joined(separator: "\n")
        return "\(name) failed (exit \(r.status)).\n\(tail.isEmpty ? "No output." : tail)"
    }

    // MARK: Process helper

    struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs a process; cancelling the calling task terminates it.
    static func run(_ exe: String, _ args: [String], cwd: URL?, env: [String: String], stdin: String?,
                    timeout: TimeInterval) async throws -> ProcessResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        cont.resume(returning: try runSync(exe, args, cwd: cwd, env: env, stdin: stdin, timeout: timeout, box: box))
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            box.terminate()
        }
    }

    final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private(set) var cancelled = false

        func set(_ p: Process) { lock.lock(); process = p; lock.unlock() }
        func terminate() {
            lock.lock()
            cancelled = true
            let p = process
            lock.unlock()
            if let p, p.isRunning { p.terminate() }
        }
    }

    static func runSync(_ exe: String, _ args: [String], cwd: URL?, env: [String: String], stdin: String?,
                        timeout: TimeInterval, box: ProcessBox = ProcessBox()) throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let input = Pipe()
        p.standardInput = stdin == nil ? FileHandle.nullDevice : input
        try p.run()
        box.set(p)
        if box.cancelled { p.terminate() }
        if let stdin {
            DispatchQueue.global().async {
                input.fileHandleForWriting.write(Data(stdin.utf8))
                try? input.fileHandleForWriting.close()
            }
        }
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        timer.cancel()
        if box.cancelled { throw CancellationError() }
        if p.terminationReason == .uncaughtSignal && !box.cancelled {
            throw AIError(message: "Timed out after \(Int(timeout)) seconds.")
        }
        return ProcessResult(status: p.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}
