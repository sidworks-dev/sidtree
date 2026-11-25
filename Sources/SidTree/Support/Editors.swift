import AppKit
import UniformTypeIdentifiers

/// The code editor SidTree opens repositories and files in (Settings → Tools).
enum EditorSettings {
    static let key = "editorAppPath"

    /// Editors SidTree offers when they are installed, by bundle identifier.
    static let known: [String] = [
        "com.jetbrains.PhpStorm", "com.jetbrains.WebStorm", "com.jetbrains.intellij", "com.jetbrains.intellij.ce",
        "com.jetbrains.pycharm", "com.jetbrains.pycharm.ce", "com.jetbrains.goland", "com.jetbrains.rubymine",
        "com.jetbrains.CLion", "com.jetbrains.rider", "com.jetbrains.fleet", "com.google.android.studio",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed",
        "com.sublimetext.4", "com.panic.Nova", "com.barebones.bbedit", "com.macromates.TextMate", "com.apple.dt.Xcode"
    ]

    struct Editor: Identifiable, Hashable {
        let url: URL
        var id: String { url.path }
        var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
        var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    }

    static func installed() -> [Editor] {
        var seen = Set<String>()
        return known.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .filter { seen.insert($0.path).inserted }
            .map(Editor.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The chosen editor, if it is still installed.
    static var current: Editor? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return Editor(url: URL(fileURLWithPath: path))
    }

    @MainActor
    static func chooseOther() -> Editor? {
        let panel = NSOpenPanel()
        panel.title = "Choose Editor"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Editor(url: url)
    }

    /// Opens a file at a line. Editors with a known command-line launcher jump to the line;
    /// others just open the file. Returns false when no editor is set.
    @MainActor
    @discardableResult
    static func open(_ url: URL, line: Int) -> Bool {
        guard let editor = current else { return false }
        guard let (tool, args) = lineCommand(for: editor.url, file: url.path, line: line) else { return open([url]) }
        let process = Process()
        process.executableURL = tool
        process.arguments = args          // passed as arguments, never through a shell
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) == nil { return open([url]) }
        NSWorkspace.shared.open(editor.url)   // bring the editor to the front
        return true
    }

    private static func lineCommand(for app: URL, file: String, line: Int) -> (URL, [String])? {
        let bundle = Bundle(url: app)
        let id = bundle?.bundleIdentifier ?? ""
        let contents = app.appendingPathComponent("Contents")
        func existing(_ path: String) -> URL? {
            let url = contents.appendingPathComponent(path)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        if id.hasPrefix("com.jetbrains.") || id == "com.google.android.studio",
           let exe = bundle?.executableURL, FileManager.default.isExecutableFile(atPath: exe.path) {
            return (exe, ["--line", String(line), file])
        }
        for cli in ["Resources/app/bin/code", "Resources/app/bin/cursor", "Resources/app/bin/windsurf"] {
            if let tool = existing(cli) { return (tool, ["-g", "\(file):\(line)"]) }
        }
        if id == "dev.zed.Zed", let tool = existing("MacOS/cli") { return (tool, ["\(file):\(line)"]) }
        if id.hasPrefix("com.sublimetext"), let tool = existing("SharedSupport/bin/subl") { return (tool, ["\(file):\(line)"]) }
        if id == "com.apple.dt.Xcode" { return (URL(fileURLWithPath: "/usr/bin/xed"), ["--line", String(line), file]) }
        if id == "com.barebones.bbedit", let tool = existing("Helpers/bbedit_tool") { return (tool, ["+\(line)", file]) }
        return nil
    }

    /// Opens `urls` in the chosen editor. Returns false when no editor is set.
    @MainActor
    @discardableResult
    static func open(_ urls: [URL]) -> Bool {
        guard let editor = current else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: editor.url, configuration: config)
        return true
    }
}
