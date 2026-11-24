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

    static func runSync(_ args: [String], in dir: URL, input: Data? = nil) -> GitResult {
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
