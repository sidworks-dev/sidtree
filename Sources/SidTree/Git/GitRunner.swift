import Foundation

struct GitResult {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var output: String { String(decoding: stdout, as: UTF8.self) }
    var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
}

struct GitError: LocalizedError, Identifiable {
    let id = UUID()
    let command: String
    let message: String

    var errorDescription: String? { message }
}

/// Thin, fast wrapper around the git CLI. Every call runs off the main thread.
enum GitRunner {
    static let gitPath: String = {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    }()

    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        // Never let read-only commands (status, diff) take the index lock / rewrite the index.
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "en_US.UTF-8"
        env["GIT_PAGER"] = "cat"
        env["PAGER"] = "cat"
        // Apps launched from Finder get a minimal PATH; make sure hooks, git-lfs, gpg etc. are found.
        var parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        where !parts.contains(extra) {
            parts.append(extra)
        }
        env["PATH"] = parts.joined(separator: ":")
        return env
    }()

    static let baseArgs = ["-c", "core.quotepath=off", "-c", "color.ui=false", "-c", "core.pager=cat"]

    static func run(_ args: [String], in dir: URL, input: Data? = nil) async -> GitResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(args, in: dir, input: input))
            }
        }
    }

    // MARK: Repository config guard

    private static let guardLock = NSLock()
    private static var fsmonitorUnsafe: [String: Bool] = [:]

    /// A repository's own `.git/config` can point `core.fsmonitor` at any program, and git runs it on every
    /// `status` — which SidTree does automatically. Opening a downloaded repository must never run its code,
    /// so only git's built-in daemon (`true`/`false`) is kept; anything else is switched off for SidTree's calls.
    static func configGuard(for dir: URL) -> [String] {
        let key = dir.standardizedFileURL.path
        guardLock.lock()
        let cached = fsmonitorUnsafe[key]
        guardLock.unlock()
        let unsafe = cached ?? {
            let value = execute(["config", "--get", "core.fsmonitor"], in: dir, input: nil).output
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let unsafe = !(value.isEmpty || ["true", "false", "yes", "no", "on", "off", "1", "0"].contains(value))
            guardLock.lock()
            fsmonitorUnsafe[key] = unsafe
            guardLock.unlock()
            return unsafe
        }()
        return unsafe ? ["-c", "core.fsmonitor=false"] : []
    }

    static func runSync(_ args: [String], in dir: URL, input: Data? = nil) -> GitResult {
        execute(configGuard(for: dir) + args, in: dir, input: input)
    }

    private static func execute(_ args: [String], in dir: URL, input: Data?) -> GitResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = baseArgs + args
        process.currentDirectoryURL = dir
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe: Pipe? = input != nil ? Pipe() : nil
        process.standardInput = inPipe ?? FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return GitResult(status: -1, stdout: Data(), stderr: Data("Could not launch git: \(error.localizedDescription)".utf8))
        }

        if let input, let inPipe {
            DispatchQueue.global(qos: .userInitiated).async {
                inPipe.fileHandleForWriting.write(input)
                try? inPipe.fileHandleForWriting.close()
            }
        }

        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return GitResult(status: process.terminationStatus, stdout: outData, stderr: errData)
    }

    /// Runs git and throws a `GitError` with git's own message when it fails.
    @discardableResult
    static func check(_ args: [String], in dir: URL, input: Data? = nil) async throws -> GitResult {
        let result = await run(args, in: dir, input: input)
        guard result.status == 0 else {
            var message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty { message = result.output.trimmingCharacters(in: .whitespacesAndNewlines) }
            if message.isEmpty { message = "git exited with status \(result.status)" }
            throw GitError(command: "git " + args.joined(separator: " "), message: message)
        }
        return result
    }
}
