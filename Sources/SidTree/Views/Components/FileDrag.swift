import AppKit
import CoreTransferable
import UniformTypeIdentifiers

/// Private staging metadata travels alongside each standard macOS file URL.
struct FileDragPayload: Codable, Equatable, Sendable, Transferable {
    static let contentType = UTType(exportedAs: "nl.sidworks.sidtree.file-drag", conformingTo: .data)
    static let pasteboardType = NSPasteboard.PasteboardType(contentType.identifier)

    let repositoryPath: String
    let kind: String
    let path: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: contentType) { payload in
            try JSONEncoder().encode(payload)
        } importing: { data in
            try JSONDecoder().decode(Self.self, from: data)
        }
    }

    static func paths(in items: [Self], from kind: String, root: URL) -> Set<String> {
        let repositoryPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return Set(items.filter { $0.kind == kind && $0.repositoryPath == repositoryPath }.map(\.path))
    }

    @MainActor
    static func draggingItems(root: URL, kind: String, files: [FileChange]) -> [NSDraggingItem] {
        let repository = root.standardizedFileURL.resolvingSymlinksInPath()
        return files.compactMap { file in
            let payload = Self(repositoryPath: repository.path, kind: kind, path: file.path)
            guard let data = try? JSONEncoder().encode(payload) else { return nil }
            let writer = NSPasteboardItem()
            writer.setData(data, forType: pasteboardType)
            let url = repository.appendingPathComponent(file.path)
            // Deleted files still support staging, but cannot be opened in another app.
            if FileManager.default.fileExists(atPath: url.path) {
                writer.setString(url.absoluteString, forType: .fileURL)
            }
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 32, height: 32), contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
    }
}
