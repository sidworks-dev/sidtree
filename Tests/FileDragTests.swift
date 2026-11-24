import AppKit
import CoreTransferable
import SwiftUI

@MainActor
final class FileDragTestState: ObservableObject {
    @Published var selection: Set<String> = []
    var focused: String?
    var doubleClicked: String?
    var toggled: [String] = []
}

private struct FileDragTestList: View {
    @ObservedObject var state: FileDragTestState
    let root: URL
    let files: [FileChange]

    var body: some View {
        FileListView(files: files, focused: nil, selection: $state.selection, checkbox: false,
                     onSelect: { state.focused = $0.id }, onToggle: { state.toggled = [$0.id] },
                     onDoubleClick: { state.doubleClicked = $0.id }, dragKind: "unstaged", dragRoot: root,
                     onToggleSelection: { state.toggled = $0.map(\.id) }) { _ in Text("File actions") }
            .background(Theme.card)
    }
}

@main
enum FileDragTests {
    enum Failure: Error { case check(String) }

    @MainActor
    static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SidTree drag tests \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ["Sources/File with spaces.php", "assets/één #%.png", "odd\nname.swift"]
        for path in paths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("test".utf8).write(to: url)
        }
        let files = paths.map { FileChange(path: $0, originalPath: nil, kind: .modified, staged: false) }
            + [FileChange(path: "deleted.php", originalPath: nil, kind: .deleted, staged: false)]
        try await checkPayloads(root: root, files: files)
        try checkInteraction(root: root, files: files)
        print("All file drag checks passed")
    }

    @MainActor
    static func checkPayloads(root: URL, files: [FileChange]) async throws {
        let items = FileDragPayload.draggingItems(root: root, kind: "staged", files: files)
        let writers = items.compactMap { $0.item as? NSPasteboardItem }
        try require(writers.count == files.count, "Each selected file has its own dragging item, including deletions")
        let payloads = try writers.map { writer -> FileDragPayload in
            guard let data = writer.data(forType: FileDragPayload.pasteboardType) else { throw Failure.check("Missing metadata") }
            return try JSONDecoder().decode(FileDragPayload.self, from: data)
        }
        try require(FileDragPayload.paths(in: payloads, from: "staged", root: root) == Set(files.map(\.path)),
                    "Internal drags preserve spaces, Unicode and newlines")
        try require(FileDragPayload.paths(in: payloads, from: "unstaged", root: root).isEmpty,
                    "Dropping back into the source list is rejected")
        try require(FileDragPayload.paths(in: payloads, from: "staged", root: root.appendingPathComponent("other")).isEmpty,
                    "Drags from another repository cannot stage unrelated files")
        try require(FileDragPayload.paths(in: payloads, from: "staged", root: root.appendingPathComponent("folder/..")).count == files.count,
                    "Equivalent repository paths are accepted")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        try require(pasteboard.writeObjects(writers), "Native pasteboard accepts the drag items")
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []).compactMap { $0 as? URL }
        let expected = files.dropLast().map { root.resolvingSymlinksInPath().appendingPathComponent($0.path) }
        try require(Set(urls.map(\.path)) == Set(expected.map(\.path)), "Editors receive every existing file as a standard file URL")
        try require(writers.last?.string(forType: .fileURL) == nil, "Missing files are not advertised as openable files")
        try require(writers.allSatisfy { $0.string(forType: .string) == nil }, "Private metadata is never exported as editor text")

        guard let data = writers.first?.data(forType: FileDragPayload.pasteboardType) else { throw Failure.check("Missing data") }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: FileDragPayload.contentType.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        let imported: FileDragPayload = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: FileDragPayload.self) { continuation.resume(with: $0) }
        }
        try require(imported == payloads.first, "SwiftUI imports the same metadata written by the native drag source")
    }

    @MainActor
    static func checkInteraction(root: URL, files: [FileChange]) throws {
        let state = FileDragTestState()
        let host = NSHostingView(rootView: FileDragTestList(state: state, root: root, files: files))
        let window = NSWindow(contentRect: NSRect(x: 70, y: 70, width: 480, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SidTree file drag checks"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        pump()
        guard let view = descendants(host).compactMap({ $0 as? FileMarqueeView }).first,
              let frame = view.dragFrames[files[0].id] else { throw Failure.check("Missing native file drag regions") }
        try require(view.hitTest(view.convert(CGPoint(x: frame.midX, y: frame.midY), to: view.superview)) === view,
                    "File labels reach the native drag source")
        let checkbox = CGPoint(x: 17, y: frame.midY)
        try require(view.hitTest(view.convert(checkbox, to: view.superview)) == nil, "Checkboxes keep their own click handling")
        try click(0, files: files, view: view, window: window)
        try require(state.selection == [files[0].id] && state.focused == files[0].id, "Clicking a draggable file still selects it and updates the diff")
        try click(1, files: files, view: view, window: window, modifiers: .command)
        try require(state.selection == Set(files[0...1].map(\.id)), "Command-click extends the selection once")
        try require(view.onDragItems(0).count == 2, "Dragging a selected row exports the entire selection")
        try require(view.onDragItems(2).count == 1, "Dragging an unselected row exports only that file")
        try click(0, files: files, view: view, window: window)
        try click(2, files: files, view: view, window: window, modifiers: .shift)
        try require(state.selection == Set(files[0...2].map(\.id)), "Shift-click still selects a range")
        try click(1, files: files, view: view, window: window, count: 2)
        try require(state.doubleClicked == files[1].id, "Double-click actions remain available")
        try sendKey("\u{F701}", keyCode: 125, window: window)
        try require(state.selection == [files[2].id], "Arrow keys still move through draggable files")
        try sendKey(" ", keyCode: 49, window: window)
        try require(state.toggled == [files[2].id], "Space still stages or unstages the selection")
    }

    @MainActor
    static func click(_ index: Int, files: [FileChange], view: FileMarqueeView, window: NSWindow,
                      modifiers: NSEvent.ModifierFlags = [], count: Int = 1) throws {
        guard let frame = view.dragFrames[files[index].id] else { throw Failure.check("Missing file frame") }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: view.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil),
                                                modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)
            else { throw Failure.check("Could not create mouse event") }
            window.sendEvent(event)
            pump()
        }
    }

    @MainActor
    static func sendKey(_ characters: String, keyCode: UInt16, window: NSWindow) throws {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, characters: characters,
                                          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
        else { throw Failure.check("Could not create key event") }
        window.sendEvent(event)
        pump()
    }

    @MainActor
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

    @MainActor
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure.check(message) }
        print("PASS: \(message)")
        fflush(stdout)
    }
}
