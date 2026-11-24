import Foundation

/// One commit mode per working copy; equivalent paths share the same setting.
enum RepositoryCommitSettings {
    private static func key(for root: URL) -> String {
        "commit.pushAfterCommit." + root.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func pushesAfterCommit(for root: URL, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(for: root))
    }

    static func save(pushAfterCommit: Bool, for root: URL, defaults: UserDefaults = .standard) {
        defaults.set(pushAfterCommit, forKey: key(for: root))
    }
}
