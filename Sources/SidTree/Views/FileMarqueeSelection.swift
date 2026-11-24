import AppKit
import SwiftUI

enum FileListMetrics {
    static let rowHeight: CGFloat = 26
    static let spacing: CGFloat = 1
    static let padding: CGFloat = 6

    static func rowFrame(_ index: Int, width: CGFloat) -> CGRect {
        CGRect(x: padding, y: padding + CGFloat(index) * (rowHeight + spacing),
               width: max(0, width - 2 * padding), height: rowHeight)
    }
}

struct FileRowContentBounds: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The overlay handles only empty space. File content and checkboxes keep their own gestures.
struct FileMarqueeSelection: NSViewRepresentable {
    let ids: [String]
    @Binding var selection: Set<String>
    let contentFrames: [String: CGRect]
    let onClick: (Int, NSEvent.ModifierFlags) -> Void
    let onFinish: (Int?) -> Void

    func makeNSView(context: Context) -> FileMarqueeView { FileMarqueeView() }

    func updateNSView(_ view: FileMarqueeView, context: Context) {
        if view.ids != ids { view.stopTracking() }
        view.ids = ids
        view.selection = selection
        view.contentFrames = Array(contentFrames.values)
        view.onSelectionChange = { selection = $0 }
        view.onClick = onClick
        view.onFinish = onFinish
    }

    static func dismantleNSView(_ view: FileMarqueeView, coordinator: ()) {
        view.stopTracking()
    }
}

final class FileMarqueeView: NSView {
    var ids: [String] = []
    var selection: Set<String> = []
    var contentFrames: [CGRect] = []
    var onSelectionChange: (Set<String>) -> Void = { _ in }
    var onClick: (Int, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var onFinish: (Int?) -> Void = { _ in }

    private var start: CGPoint?
    private var initialSelection: Set<String> = []
    private var modifiers: NSEvent.ModifierFlags = []
    private(set) var selectionRect: CGRect?
    private var dragEvent: NSEvent?
    private var scrollTimer: Timer?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint), !isHidden else { return nil }
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || event.modifierFlags.contains(.control) { return nil }
        return contentFrames.contains(where: { $0.contains(localPoint) }) ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        initialSelection = selection
        modifiers = event.modifierFlags
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard selectionRect != nil || hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
        dragEvent = event
        if scrollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self, let event = self.dragEvent else { return }
                if self.autoscroll(with: event) {
                    self.updateSelection(to: self.convert(event.locationInWindow, from: nil))
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            scrollTimer = timer
        }
        autoscroll(with: event)
        updateSelection(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        if selectionRect != nil {
            updateSelection(to: convert(event.locationInWindow, from: nil))
            finishSelection()
        } else {
            let flags = modifiers
            let index = row(at: start)
            stopTracking()
            if let index {
                onClick(index, flags)
            } else if flags.isDisjoint(with: [.command, .shift]) {
                setSelection([])
                onFinish(nil)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, start != nil { cancelSelection() } else { super.keyDown(with: event) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        }
        stopTracking()
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                                                   name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    @objc private func windowResignedKey(_ notification: Notification) { cancelSelection() }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = selectionRect, !rect.isNull, !rect.isEmpty else { return }
        let path = NSBezierPath(rect: rect)
        Theme.nsAccent.withAlphaComponent(0.12).setFill()
        path.fill()
        Theme.nsAccent.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func row(at point: CGPoint) -> Int? {
        let index = Int(floor((point.y - FileListMetrics.padding) / (FileListMetrics.rowHeight + FileListMetrics.spacing)))
        guard ids.indices.contains(index), FileListMetrics.rowFrame(index, width: bounds.width).contains(point) else { return nil }
        return index
    }

    private func updateSelection(to point: CGPoint) {
        guard let start else { return }
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: max(1, abs(point.x - start.x)), height: max(1, abs(point.y - start.y))).intersection(bounds)
        selectionRect = rect
        needsDisplay = true
        var hits: Set<String> = []
        if !rect.isNull, !ids.isEmpty {
            let first = max(0, Int(floor((rect.minY - FileListMetrics.padding) / (FileListMetrics.rowHeight + FileListMetrics.spacing))))
            let last = min(ids.count - 1, Int(floor((rect.maxY - FileListMetrics.padding) / (FileListMetrics.rowHeight + FileListMetrics.spacing))))
            if first <= last {
                for index in first...last where FileListMetrics.rowFrame(index, width: bounds.width).intersects(rect) {
                    hits.insert(ids[index])
                }
            }
        }
        let result = modifiers.contains(.command) ? initialSelection.symmetricDifference(hits)
            : modifiers.contains(.shift) ? initialSelection.union(hits) : hits
        setSelection(result.intersection(ids))
    }

    private func setSelection(_ ids: Set<String>) {
        guard selection != ids else { return }
        selection = ids
        onSelectionChange(ids)
    }

    private func finishSelection() {
        let index = ids.firstIndex(where: { selection.contains($0) })
        stopTracking()
        onFinish(index)
    }

    func cancelSelection() {
        guard start != nil else { return }
        setSelection(initialSelection.intersection(ids))
        stopTracking()
    }

    func stopTracking() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        dragEvent = nil
        start = nil
        selectionRect = nil
        needsDisplay = true
    }
}
