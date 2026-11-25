import Foundation

/// The folder new repositories are opened from and cloned into (Settings → General).
enum ProjectFolder {
    static let key = "defaultProjectFolder"

    static var url: URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Paths as people read them: "~/Development" instead of "/Users/me/Development",
/// also when the path was resolved through a symlink (e.g. /private/tmp, a linked home folder).
enum DisplayPath {
    private static let homes: [String] = {
        let home = NSHomeDirectory()
        let resolved = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        return Array(Set([home, resolved, "/private" + home])).sorted { $0.count > $1.count }
    }()

    static func of(_ path: String) -> String {
        for home in homes where path == home || path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func of(_ url: URL) -> String { of(url.path) }

    /// The folder that contains `url`, e.g. "~/Development" for a repository.
    static func parent(of url: URL) -> String { of(url.deletingLastPathComponent()) }
}
