import AppKit
import SwiftUI

enum FileListMetrics {
    static let rowHeight: CGFloat = 30
    static let spacing: CGFloat = 0
    static let padding: CGFloat = 6

    static func rowFrame(_ index: Int, width: CGFloat) -> CGRect {
        CGRect(x: padding, y: padding + CGFloat(index) * (rowHeight + spacing),
               width: max(0, width - 2 * padding), height: rowHeight)
    }
}

struct FileRowBounds {
    var content: [String: Anchor<CGRect>] = [:]
    var draggable: [String: Anchor<CGRect>] = [:]
}

struct FileRowContentBounds: PreferenceKey {
    static var defaultValue: FileRowBounds { FileRowBounds() }
    static func reduce(value: inout FileRowBounds, nextValue: () -> FileRowBounds) {
        let next = nextValue()
        value.content.merge(next.content, uniquingKeysWith: { _, new in new })
        value.draggable.merge(next.draggable, uniquingKeysWith: { _, new in new })
    }
}

/// Empty space starts selection; file labels start native file drags. Checkboxes keep their own gestures.
struct FileMarqueeSelection: NSViewRepresentable {
    let ids: [String]
    @Binding var selection: Set<String>
    let contentFrames: [String: CGRect]
    let onClick: (Int, NSEvent.ModifierFlags) -> Void
    let onFinish: (Int?) -> Void
    var dragFrames: [String: CGRect] = [:]
    var onDoubleClick: (Int) -> Void = { _ in }
    var onDragItems: (Int) -> [NSDraggingItem] = { _ in [] }
    /// The row under the pointer (this view covers the rows, so it tracks hover for them).
    var onHover: (Int?) -> Void = { _ in }

    func makeNSView(context: Context) -> FileMarqueeView { FileMarqueeView() }

    func updateNSView(_ view: FileMarqueeView, context: Context) {
        if view.ids != ids { view.stopTracking() }
        view.ids = ids
        view.selection = selection
        view.contentFrames = Array(contentFrames.values)
        view.dragFrames = dragFrames
        view.onSelectionChange = { selection = $0 }
        view.onClick = onClick
        view.onFinish = onFinish
        view.onDoubleClick = onDoubleClick
        view.onDragItems = onDragItems
        view.onHover = onHover
    }

    static func dismantleNSView(_ view: FileMarqueeView, coordinator: ()) {
        view.stopTracking()
    }
}

final class FileMarqueeView: NSView, NSDraggingSource {
    var ids: [String] = [] {
        didSet { if ids != oldValue { window?.invalidateCursorRects(for: self) } }
    }
    var selection: Set<String> = []
    var contentFrames: [CGRect] = []
    var dragFrames: [String: CGRect] = [:]
    var onSelectionChange: (Set<String>) -> Void = { _ in }
    var onClick: (Int, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var onFinish: (Int?) -> Void = { _ in }
    var onDoubleClick: (Int) -> Void = { _ in }
    var onDragItems: (Int) -> [NSDraggingItem] = { _ in [] }
    var onHover: (Int?) -> Void = { _ in }
    private var hovered: Int?

    private var start: CGPoint?
    private var initialSelection: Set<String> = []
    private var modifiers: NSEvent.ModifierFlags = []
    private(set) var selectionRect: CGRect?
    private var dragEvent: NSEvent?
    private var scrollTimer: Timer?
    private var dragIndex: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { setHovered(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseEntered(with event: NSEvent) { setHovered(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func setHovered(_ index: Int?) {
        guard index != hovered else { return }
        hovered = index
        onHover(index)
    }

    /// Rows are clickable: show the pointing hand over them.
    override func resetCursorRects() {
        for index in ids.indices {
            addCursorRect(FileListMetrics.rowFrame(index, width: bounds.width), cursor: .pointingHand)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint), !isHidden else { return nil }
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || event.modifierFlags.contains(.control) { return nil }
        if dragFrames.values.contains(where: { $0.contains(localPoint) }) { return self }
        return contentFrames.contains(where: { $0.contains(localPoint) }) ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        initialSelection = selection
        modifiers = event.modifierFlags
        if let start, let index = row(at: start), dragFrames[ids[index]]?.contains(start) == true {
            dragIndex = index
        }
        if dragIndex == nil { window?.makeFirstResponder(self) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard selectionRect != nil || hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
        if let dragIndex {
            let items = onDragItems(dragIndex)
            guard !items.isEmpty else { stopTracking(); return }
            for item in items { item.draggingFrame.origin = CGPoint(x: point.x - 16, y: point.y - 16) }
            stopTracking()
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.draggingFormation = .stack
            return
        }
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
                if event.clickCount == 2 { onDoubleClick(index) }
            } else if flags.isDisjoint(with: [.command, .shift]) {
                setSelection([])
                onFinish(nil)
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
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
        dragIndex = nil
        start = nil
        selectionRect = nil
        needsDisplay = true
    }
}
