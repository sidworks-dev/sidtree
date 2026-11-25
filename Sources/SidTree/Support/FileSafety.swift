import Foundation
import UniformTypeIdentifiers

/// Repository files are untrusted: opening one with its default app must never run code.
enum FileSafety {
    private static let runnable: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "action", "scpt", "scptd", "applescript", "osax",
        "pkg", "mpkg", "jar", "webloc", "inetloc", "fileloc", "url", "prefpane", "saver", "kext", "shortcut",
        "definition", "plugin", "bundle", "framework", "xpc", "systemextension", "mobileconfig", "dmg"
    ]

    /// Why opening `url` with its default app is unsafe, or nil when it is an ordinary document.
    static func blockReason(_ url: URL, root: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        let base = root.resolvingSymlinksInPath().path + "/"
        guard resolved.path.hasPrefix(base) else { return "it points outside the repository" }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return "it is a folder or app bundle" }
        let ext = resolved.pathExtension.lowercased()
        if runnable.contains(ext) { return "it could run code" }
        if let type = UTType(filenameExtension: ext),
           type.conforms(to: .application) || type.conforms(to: .applicationBundle) || type.conforms(to: .unixExecutable) {
            return "it could run code"
        }
        // Executables without an extension open in Terminal and run.
        if ext.isEmpty && FileManager.default.isExecutableFile(atPath: resolved.path) { return "it is an executable" }
        return nil
    }
}
