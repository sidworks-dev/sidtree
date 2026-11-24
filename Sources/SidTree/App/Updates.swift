import AppKit
import SwiftUI

// MARK: - Versions

struct Version: Comparable, CustomStringConvertible {
    let parts: [Int]

    init(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        parts = trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    static func < (a: Version, b: Version) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
    var description: String { parts.map(String.init).joined(separator: ".") }

    static let current = Version(AppInfo.version)
}

// MARK: - Changelog

struct ChangelogEntry: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let body: String
}

enum Changelog {
    /// Parses a Keep-a-Changelog style file: `## [1.2.0] - 2026-11-24` headings.
    static func parse(_ text: String) -> [ChangelogEntry] {
        var entries: [ChangelogEntry] = []
        var current: (String, String)?
        var body: [String] = []
        func flush() {
            if let (v, d) = current {
                entries.append(ChangelogEntry(version: v, date: d, body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            body = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                let heading = line.dropFirst(3)
                let version = heading.split(separator: "]").first.map { $0.replacingOccurrences(of: "[", with: "") }
                    ?? String(heading.split(separator: " ").first ?? "")
                let date = heading.components(separatedBy: " - ").dropFirst().first ?? ""
                current = (version.trimmingCharacters(in: .whitespaces), date.trimmingCharacters(in: .whitespaces))
            } else if current != nil {
                body.append(line)
            }
        }
        flush()
        return entries.filter { $0.version.lowercased() != "unreleased" }
    }

    static var bundled: [ChangelogEntry] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }
}

/// Renders the small markdown subset used in the changelog and release notes.
struct MarkdownNotes: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("### ") {
                    Text(String(line.dropFirst(4)).uppercased())
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 6)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(Theme.secondaryText.opacity(0.6)).frame(width: 4, height: 4).offset(y: -2)
                        Text(inline(String(line.dropFirst(2)))).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !line.isEmpty {
                    Text(inline(line)).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

// MARK: - What's New

enum WhatsNew {
    private static let key = "lastSeenVersion"

    /// True once after the app was updated (not on a first install).
    static func shouldShowAfterUpdate() -> Bool {
        let d = UserDefaults.standard
        let last = d.string(forKey: key)
        d.set(AppInfo.version, forKey: key)
        guard let last else { return false }
        return Version(last) < Version.current && !Changelog.bundled.isEmpty
    }

    static var previousVersion: String?
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    private let entries = Changelog.bundled

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LogoMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's New in SidTree").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Version \(AppInfo.version)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(20)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if entries.isEmpty {
                        Text("No release notes available.").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(entry.version).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                if entry.version == AppInfo.version {
                                    SoftBadge(text: "Current", color: Theme.accent, background: Theme.violetSoft)
                                }
                                Spacer()
                                Text(entry.date).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                            }
                            MarkdownNotes(text: entry.body)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.border))
                    }
                }
                .padding(20)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                Spacer()
                Button("Continue") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.subtle)
        }
        .frame(width: 560, height: 560)
        .background(Theme.canvas)
        .tint(Theme.accent)
    }
}

// MARK: - Update checker

struct ReleaseInfo: Equatable {
    let tag: String
    let version: Version
    let notes: String
    let pageURL: URL
    let assetName: String?
    let assetURL: URL?
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repo = "sidworks-dev/sidtree"
    static let repoURL = URL(string: "https://github.com/\(repo)")!

    @Published var available: ReleaseInfo?
    @Published var latest: ReleaseInfo?
    @Published var checking = false
    @Published var installing = false
    @Published var message: String?

    private let lastCheckKey = "update.lastCheck"
    static let autoCheckKey = "update.autoCheck"

    /// Checks at most every 6 hours unless the user asked.
    static let startupKey = "update.checkOnStartup"
    private let announcedKey = "update.announcedVersion"
    private var timer: Timer?

    /// On launch: check right away (if enabled) and show the update window once per new version;
    /// while running, check again every 6 hours (if enabled).
    func startAutomaticChecks(openWindow: OpenWindowAction) {
        let d = UserDefaults.standard
        if d.object(forKey: Self.startupKey) as? Bool ?? true {
            Task {
                await check(userInitiated: false)
                if let release = available, ProcessInfo.processInfo.environment["SIDTREE_DEBUG_AUTOINSTALL"] != nil {
                    await install(release)   // test hook: what "Install & Relaunch" does
                    return
                }
                if let release = available, d.string(forKey: announcedKey) != release.version.description {
                    d.set(release.version.description, forKey: announcedKey)
                    openWindow(id: "update")
                }
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in UpdateChecker.shared.checkIfDue() }
        }
    }

    func checkIfDue() {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.autoCheckKey) as? Bool ?? true else { return }
        let last = d.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }

    /// A local release.json (GitHub release format) used instead of GitHub, for testing updates.
    /// Set with the `SIDTREE_UPDATE_FEED` environment variable or the `update.feed` default.
    static var localFeed: URL? {
        let path = ProcessInfo.processInfo.environment["SIDTREE_UPDATE_FEED"] ?? UserDefaults.standard.string(forKey: "update.feed")
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    func check(userInitiated: Bool) async {
        guard !checking else { return }
        checking = true
        message = nil
        defer { checking = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        do {
            let release = try await fetchLatest()
            latest = release
            available = release.version > Version.current ? release : nil
            if available == nil && userInitiated { message = "SidTree \(AppInfo.version) is the latest version." }
        } catch {
            if userInitiated { message = error.localizedDescription }
        }
    }

    /// GitHub's public API first; the GitHub CLI (when installed) is a fallback, e.g. when rate-limited.
    private func fetchLatest() async throws -> ReleaseInfo {
        if let feed = Self.localFeed {
            guard let data = try? Data(contentsOf: feed), let info = Self.parse(data) else {
                throw AIError(message: "The local update feed at \(feed.path) could not be read.")
            }
            return info
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200, let info = Self.parse(data) {
            return info
        }
        guard let gh = Self.ghPath else {
            throw AIError(message: "Could not reach GitHub to check for updates. Check your internet connection and try again.")
        }
        let r = try await AICommitGenerator.run(gh, ["api", "repos/\(Self.repo)/releases/latest"], cwd: nil,
                                                env: Self.env, stdin: nil, timeout: 20)
        guard r.status == 0, let info = Self.parse(Data(r.stdout.utf8)) else {
            let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIError(message: detail.contains("Not Found") ? "No releases published yet." : "Update check failed: \(detail)")
        }
        return info
    }

    private static func parse(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        return ReleaseInfo(tag: tag, version: Version(tag), notes: json["body"] as? String ?? "", pageURL: page,
                           assetName: zip?["name"] as? String,
                           assetURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)))
    }

    private static var env: [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = AICommitGenerator.searchPath
        return e
    }

    static var ghPath: String? {
        AICommitGenerator.searchPath.split(separator: ":").map { "\($0)/gh" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Install

    /// Downloads the release zip, swaps the app bundle once SidTree has quit, and relaunches.
    func install(_ release: ReleaseInfo) async {
        guard !installing else { return }
        installing = true
        message = nil
        defer { installing = false }
        do {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("sidtree-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = try await download(release, to: work)

            let extract = work.appendingPathComponent("extract")
            let unzip = try await AICommitGenerator.run("/usr/bin/ditto", ["-x", "-k", zip.path, extract.path],
                                                        cwd: nil, env: Self.env, stdin: nil, timeout: 120)
            guard unzip.status == 0 else { throw AIError(message: "Could not unpack the update: \(unzip.stderr)") }
            guard let newApp = try fm.contentsOfDirectory(at: extract, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw AIError(message: "The update does not contain an app.") }

            let dest = Bundle.main.bundleURL
            guard fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
                throw AIError(message: "No permission to replace \(dest.path). Download the update manually.")
            }
            let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(dest.path).old"
            mv "\(dest.path)" "\(dest.path).old" && /usr/bin/ditto "\(newApp.path)" "\(dest.path)" && rm -rf "\(dest.path).old"
            [ -d "\(dest.path)" ] || mv "\(dest.path).old" "\(dest.path)"
            /usr/bin/xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
            /usr/bin/open "\(dest.path)"
            rm -rf "\(work.path)"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            message = error.localizedDescription
        }
    }

    private func download(_ release: ReleaseInfo, to dir: URL) async throws -> URL {
        if let url = release.assetURL, url.isFileURL {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        }
        if let url = release.assetURL {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            if let (tmp, response) = try? await URLSession.shared.download(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                let dest = dir.appendingPathComponent(release.assetName ?? "SidTree.zip")
                try FileManager.default.moveItem(at: tmp, to: dest)
                return dest
            }
        }
        guard let gh = Self.ghPath else {
            throw AIError(message: "The update could not be downloaded. Try again, or download it from the releases page.")
        }
        let r = try await AICommitGenerator.run(gh, ["release", "download", release.tag, "-R", Self.repo,
                                                     "-p", "*.zip", "-D", dir.path, "--clobber"],
                                                cwd: nil, env: Self.env, stdin: nil, timeout: 300)
        guard r.status == 0,
              let zip = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "zip" }) else {
            throw AIError(message: "Download failed: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return zip
    }
}

struct UpdateView: View {
    @ObservedObject private var checker = UpdateChecker.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LogoMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("You have SidTree \(AppInfo.version)").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if checker.checking { ProgressView().controlSize(.small) }
            }
            .padding(20)
            Rectangle().fill(Theme.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let release = checker.available {
                        Text("What's new in \(release.version.description)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                        MarkdownNotes(text: release.notes.isEmpty ? "No release notes." : release.notes)
                    } else if let message = checker.message {
                        Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText).textSelection(.enabled)
                    } else if checker.checking {
                        Text("Checking for updates…").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("SidTree is up to date.").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                    }
                    if checker.available != nil, let message = checker.message {
                        Text(message).font(.system(size: 12)).foregroundStyle(Theme.red).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                if checker.installing {
                    ProgressView().controlSize(.small)
                    Text("Downloading…").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if let release = checker.available {
                    Button("View on GitHub") { NSWorkspace.shared.open(release.pageURL) }.buttonStyle(PillButtonStyle())
                    Button("Later") { dismiss() }.buttonStyle(PillButtonStyle())
                    Button("Install & Relaunch") { Task { await checker.install(release) } }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(checker.installing)
                } else {
                    Button("Check Again") { Task { await checker.check(userInitiated: true) } }
                        .buttonStyle(PillButtonStyle())
                        .disabled(checker.checking)
                    Button("Close") { dismiss() }.buttonStyle(PillButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.subtle)
        }
        .frame(width: 520, height: 440)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .task { if checker.latest == nil && !checker.checking { await checker.check(userInitiated: true) } }
    }

    private var title: String {
        if let r = checker.available { return "SidTree \(r.version.description) is available" }
        return "Software Update"
    }
}

/// Small "Update" pill for the sidebar header.
struct UpdateBadge: View {
    @ObservedObject private var checker = UpdateChecker.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let release = checker.available {
            Button { openWindow(id: "update") } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 10))
                    Text(release.version.description)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Theme.action, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("SidTree \(release.version.description) is available")
        }
    }
}

/// Runs once per launch from the first window: What's New after an update and the periodic update check.
enum LaunchTasks {
    private static var done = false

    @MainActor
    static func run(openWindow: OpenWindowAction) {
        guard !done else { return }
        done = true
        if WhatsNew.shouldShowAfterUpdate() { openWindow(id: "whats-new") }
        UpdateChecker.shared.startAutomaticChecks(openWindow: openWindow)
    }
}
