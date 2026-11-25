import AppKit
import SwiftUI

enum WindowChrome {
    static let tabStripHeight: CGFloat = 40
    /// Centre of the close button from the window's left edge; the other two follow at 20pt steps.
    static let firstButtonCenterX: CGFloat = 22
    /// Space the traffic lights take before the first tab.
    static let tabsLeading: CGFloat = 86
}

/// Moves the traffic lights to the vertical centre of the tab strip, and keeps them there
/// when AppKit lays out the title bar again (resizing, key changes, full screen).
@MainActor
final class TrafficLightPositioner: NSObject {
    private weak var window: NSWindow?
    private var applying = false
    private var observers: [NSObjectProtocol] = []

    init(window: NSWindow) {
        self.window = window
        super.init()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didExitFullScreenNotification, NSWindow.didChangeBackingPropertiesNotification
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
        if let close = window.standardWindowButton(.closeButton) {
            close.postsFrameChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: close, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            })
        }
        apply()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func apply() {
        guard !applying, let window, !window.styleMask.contains(.fullScreen) else { return }
        applying = true
        defer { applying = false }
        let centerY = window.frame.height - WindowChrome.tabStripHeight / 2
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            let center = parent.convert(NSPoint(x: WindowChrome.firstButtonCenterX + CGFloat(index) * 20, y: centerY), from: nil)
            let origin = NSPoint(x: (center.x - button.frame.width / 2).rounded(), y: (center.y - button.frame.height / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// Browser-style repository tabs in the window's title bar area.
struct TabStrip: View {
    let workspace: Workspace
    @State private var dragging: UUID?

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(workspace.tabs) { tab in
                TabItem(tab: tab, model: tab.model, active: tab.id == workspace.activeID,
                        select: { workspace.activate(tab.id) },
                        close: { workspace.close(tab.id) })
                    .contextMenu { menu(for: tab) }
                    .onDrag {
                        dragging = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: TabDropDelegate(target: tab.id, workspace: workspace, dragging: $dragging))
            }
            // On the repositories overview the "+" has nothing to add: that screen is where it leads.
            if workspace.activeID != nil {
                NewTabButton { workspace.showOverview() }
                    .padding(.leading, 4)
                    .padding(.bottom, 4)
            }
            Spacer(minLength: 12)
            UpdateBadge()
                .padding(.bottom, 9)
        }
        .padding(.leading, WindowChrome.tabsLeading)
        .padding(.trailing, 10)
        .frame(height: WindowChrome.tabStripHeight, alignment: .bottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowDragArea())
        .background(Theme.chrome)
    }

    @ViewBuilder
    private func menu(for tab: RepoTab) -> some View {
        Button("Close Tab") { workspace.close(tab.id) }
        Button("Close Other Tabs") { workspace.closeOthers(tab.id) }
            .disabled(workspace.tabs.count < 2)
        Divider()
        Button("Open in \(tab.model.editorName)") { tab.model.openInEditor() }
        Button("Show in Finder") { tab.model.showInFinder() }
        Button("Open in Terminal") { tab.model.openTerminal() }
        Button("Open Remote in Browser") { tab.model.openRemoteInBrowser() }
            .disabled(tab.model.remotes.isEmpty)
        Divider()
        Button("Copy Path") { tab.model.copyToPasteboard(tab.root.path) }
    }
}

private struct TabDropDelegate: DropDelegate {
    let target: UUID
    let workspace: Workspace
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.12)) { workspace.move(dragging, before: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct TabItem: View {
    let tab: RepoTab
    let model: RepoModel
    let active: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hover = false
    @State private var hoverClose = false

    var body: some View {
        HStack(spacing: 8) {
            Text(String(model.name.prefix(1)).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.accent)
                .frame(width: 18, height: 18)
                .background(active ? Theme.action : Theme.tileFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(model.name)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active || hover ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 24, maxWidth: 160, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Circle()
                .fill(model.hasLocalChanges ? Theme.orange : .clear)
                .frame(width: 6, height: 6)
                .help(model.hasLocalChanges ? "\(model.changeCount) changed files" : "")
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(hoverClose ? Theme.text : Theme.tertiaryText)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(hoverClose ? Color(nsColor: Theme.dynamic(0xE3DFD8, 0x55504B)) : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .onHover { hoverClose = $0 }
            .help("Close tab (⌘W)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background {
            if active {
                TabShape().fill(Theme.sidebar)
                TabShape(open: true).stroke(Theme.border, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .background(MiddleClick(action: close))
        .handCursor()
        .onTapGesture(perform: select)
        .onHover { hover = $0 }
        .help(DisplayPath.of(tab.root))
    }
}

/// Tab outline with rounded top corners; `open` leaves out the bottom edge so the tab flows into the toolbar.
private struct TabShape: Shape {
    var open = false
    var radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: rect.maxY + (open ? 1 : 0)))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: rect.maxY + (open ? 1 : 0)))
        if !open { p.closeSubpath() }
        return p
    }
}

private struct NewTabButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(hover ? Theme.text : Theme.secondaryText)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hover ? Theme.subtle : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
        .help("Open repository (⌘T)")
    }
}

/// Middle-click on a tab closes it, as in browsers. SwiftUI has no middle-click gesture, so a local
/// event monitor checks whether the click landed inside this view; other clicks pass through.
private struct MiddleClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickView { MiddleClickView() }
    func updateNSView(_ view: MiddleClickView, context: Context) { view.action = action }

    final class MiddleClickView: NSView {
        var action: () -> Void = {}
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
                guard let self, event.buttonNumber == 2, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.action()
                return nil
            }
        }
    }
}
