import AppKit

final class RecentRepos: ObservableObject {
    static let shared = RecentRepos()
    private let key = "recentRepositories"
    @Published private(set) var urls: [URL] = []

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        var list = urls.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url, at: 0)
        urls = Array(list.prefix(20))
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    func clear() {
        urls = []
        save()
    }

    private func save() { UserDefaults.standard.set(urls.map(\.path), forKey: key) }
}

enum RepoPicker {
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Repository"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let folder = ProjectFolder.url { panel.directoryURL = folder }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
