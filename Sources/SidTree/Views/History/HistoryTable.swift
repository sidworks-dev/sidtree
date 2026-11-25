import AppKit
import SwiftUI

/// High-performance commit list backed by NSTableView. Rows are drawn manually; no SwiftUI per row.
struct HistoryTable: NSViewRepresentable {
    let model: RepoModel
    let version: Int
    let selectedID: String?
    let scrollToken: Int
    let filtering: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = PointingTableView()
        table.style = .fullWidth
        table.rowHeight = 34
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = false
        table.backgroundColor = Theme.nsCanvas

        for (id, title, width, min) in [
            ("graph", "Graph", 60.0, 30.0),
            ("description", "Description", 420.0, 160.0),
            ("author", "Author", 112.0, 60.0),
            ("date", "Date", 124.0, 80.0),
            ("hash", "Commit", 82.0, 50.0)
        ] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.headerCell = HistoryHeaderCell(textCell: title)
            col.title = title
            col.width = width
            col.minWidth = min
            col.resizingMask = id == "description" ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            table.addTableColumn(col)
        }
        // Description takes the remaining width; the fixed columns keep their size.
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.autosaveName = "SidTreeHistoryTable.v2"
        table.autosaveTableColumns = true

        let header = OpaqueHeaderView()
        header.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        table.headerView = header

        let headerMenu = NSMenu()
        headerMenu.delegate = context.coordinator
        headerMenu.identifier = NSUserInterfaceItemIdentifier("header")
        table.headerView?.menu = headerMenu

        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu

        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.sync(version: version, selectedID: selectedID, scrollToken: scrollToken, filtering: filtering)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        let model: RepoModel
        weak var table: NSTableView?
        private var rows: [HistoryRow] = []
        private var index: [String: Int] = [:]
        private var branchByName: [String: Branch] = [:]
        private var version = -1
        private var scrollToken = 0
        private var syncingSelection = false
        private var filtering = false
        private var adjustingGraph = false
        static let graphWidthKey = "history.graphWidth"

        init(model: RepoModel) { self.model = model }

        /// Remembers the graph width once the user drags it.
        func tableViewColumnDidResize(_ notification: Notification) {
            guard !adjustingGraph, let table, table.inLiveResize == false,
                  let col = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  col.identifier.rawValue == "graph", NSEvent.pressedMouseButtons & 1 == 1 else { return }
            UserDefaults.standard.set(Double(col.width), forKey: Self.graphWidthKey)
        }

        func sync(version: Int, selectedID: String?, scrollToken: Int, filtering: Bool) {
            guard let table else { return }
            if version != self.version {
                self.version = version
                rows = model.displayRows
                index = [:]
                index.reserveCapacity(rows.count)
                for (i, r) in rows.enumerated() { index[r.commit.id] = i }
                branchByName = Dictionary(model.localBranches.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                self.filtering = filtering
                syncingSelection = true
                table.reloadData()
                syncingSelection = false
                adjustGraphColumn()
            }
            let currentRow = table.selectedRow
            let currentID = currentRow >= 0 && currentRow < rows.count ? rows[currentRow].commit.id : nil
            if currentID != selectedID {
                syncingSelection = true
                if let selectedID, let idx = index[selectedID] {
                    table.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                } else {
                    table.deselectAll(nil)
                }
                syncingSelection = false
            }
            if scrollToken != self.scrollToken {
                self.scrollToken = scrollToken
                if let id = model.scrollRequest?.id, let idx = index[id] {
                    scrollToCenter(idx)
                }
            }
        }

        private func scrollToCenter(_ row: Int) {
            guard let table, let clip = table.enclosingScrollView?.contentView else { return }
            let rect = table.rect(ofRow: row)
            // The column header sits on top of the rows (content inset), so the top-most
            // position is -inset, not 0; clamp so short lists never scroll under the header.
            let insetTop = clip.contentInsets.top
            let insetBottom = clip.contentInsets.bottom
            let visible = clip.bounds.height - insetTop - insetBottom
            let minY = -insetTop
            let maxY = max(minY, table.frame.height - clip.bounds.height + insetBottom)
            let y = min(max(rect.midY - visible / 2 - insetTop, minY), maxY)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            table.enclosingScrollView?.reflectScrolledClipView(clip)
        }

        private func adjustGraphColumn() {
            guard let table, let col = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("graph")) else { return }
            col.isHidden = false
            // A width the user dragged to wins; otherwise fit the lanes, but never more than ~4 of them:
            // the description matters more, and wide graphs are clipped until the column is dragged wider.
            let saved = UserDefaults.standard.double(forKey: Self.graphWidthKey)
            var lanes = 1
            for row in rows { lanes = max(lanes, row.graph.width) }
            let width = saved > 0 ? CGFloat(saved) : min(max(CGFloat(lanes) * GraphCellView.laneWidth + 26, 48), 82)
            guard abs(col.width - width) > 0.5 else { return }
            adjustingGraph = true
            col.width = width
            table.sizeToFit()   // the description column absorbs the change, so nothing scrolls sideways
            adjustingGraph = false
        }

        // Data source
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row < rows.count else { return nil }
            let item = rows[row]
            let id = tableColumn.identifier
            switch id.rawValue {
            case "graph":
                let view = (tableView.makeView(withIdentifier: id, owner: nil) as? GraphCellView) ?? GraphCellView()
                view.identifier = id
                view.configure(item.graph, commit: item.commit, dotOnly: filtering)
                return view
            case "description":
                let view = (tableView.makeView(withIdentifier: id, owner: nil) as? DescriptionCellView) ?? DescriptionCellView()
                view.identifier = id
                view.configure(commit: item.commit, color: item.graph.color, branches: branchByName)
                return view
            default:
                let view = (tableView.makeView(withIdentifier: id, owner: nil) as? TextCellView) ?? TextCellView(monospaced: id.rawValue == "hash")
                view.identifier = id
                let c = item.commit
                if c.isWorkingCopy {
                    view.set("")
                } else {
                    switch id.rawValue {
                    case "date": view.set(Formatters.historyDate(c.date), tooltip: Formatters.full.string(from: c.date))
                    case "author": view.set(c.author, tooltip: c.email)
                    default: view.set(c.shortHash, tooltip: c.id)
                    }
                }
                return view
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            HistoryRowView()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !syncingSelection, let table else { return }
            let row = table.selectedRow
            let id = row >= 0 && row < rows.count ? rows[row].commit.id : nil
            model.selectCommit(id)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let table, table.clickedRow >= 0, table.clickedRow < rows.count else { return }
            let commit = rows[table.clickedRow].commit
            if commit.isWorkingCopy {
                model.sidebarSelection = .changes
            } else if let branch = commit.refs.first(where: { $0.kind == .localBranch && !$0.isCurrent }) {
                model.checkout(localName: branch.name)
            }
        }

        @objc func scrolled(_ note: Notification) {
            guard !filtering, let table, model.canLoadMore, !model.historyLoading else { return }
            let visible = table.rows(in: table.visibleRect)
            if visible.location + visible.length > rows.count - 150 {
                model.loadMoreHistory()
            }
        }

        // MARK: Menus

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            if menu.identifier?.rawValue == "header" {
                buildHeaderMenu(menu)
                return
            }
            guard let table, table.clickedRow >= 0, table.clickedRow < rows.count else { return }
            let commit = rows[table.clickedRow].commit
            if commit.isWorkingCopy {
                menu.addItem(ClosureMenuItem("Show Changes") { [model] in model.sidebarSelection = .changes })
                return
            }
            buildCommitMenu(menu, commit: commit)
        }

        private func buildHeaderMenu(_ menu: NSMenu) {
            guard let table else { return }
            for col in table.tableColumns where col.identifier.rawValue != "description" {
                let item = ClosureMenuItem(col.title) { col.isHidden.toggle() }
                item.state = col.isHidden ? .off : .on
                menu.addItem(item)
            }
        }

        private func buildCommitMenu(_ menu: NSMenu, commit: Commit) {
            let m = model
            let current = m.currentBranch

            let localRefs = commit.refs.filter { $0.kind == .localBranch }
            let remoteRefs = commit.refs.filter { $0.kind == .remoteBranch && !$0.name.hasSuffix("/HEAD") }
            for ref in localRefs where !ref.isCurrent {
                menu.addItem(ClosureMenuItem("Checkout \(ref.name)") { m.checkout(localName: ref.name) })
            }
            for ref in remoteRefs {
                if let b = m.remoteBranches.first(where: { $0.name == ref.name }) {
                    menu.addItem(ClosureMenuItem("Checkout \(ref.name)") { m.checkout(branch: b) })
                }
            }
            menu.addItem(ClosureMenuItem("Checkout Commit (detached)") { m.checkoutDetached(commit.id) })
            menu.addItem(.separator())

            if let current {
                let mergeTarget = localRefs.first(where: { !$0.isCurrent })?.name ?? remoteRefs.first?.name ?? commit.id
                let label = mergeTarget == commit.id ? commit.shortHash : mergeTarget
                menu.addItem(ClosureMenuItem("Merge \(label) into \(current)") { m.sheet = .merge(mergeTarget) })
                menu.addItem(ClosureMenuItem("Rebase \(current) onto \(label)") { m.sheet = .rebase(mergeTarget) })
            }
            menu.addItem(ClosureMenuItem("New Branch from Here") { m.sheet = .newBranch(startPoint: commit.id) })
            menu.addItem(ClosureMenuItem("New Tag") { m.sheet = .tag(commit.id) })
            let tagRefs = commit.refs.filter { $0.kind == .tag }
            for ref in tagRefs {
                menu.addItem(ClosureMenuItem("Edit Tag \(ref.name)") { m.sheet = .editTag(ref.name, target: nil) })
                menu.addItem(ClosureMenuItem("Delete Tag \(ref.name)") { m.sheet = .deleteTag(ref.name) })
            }
            let movable = m.tags.filter { t in !tagRefs.contains { $0.name == t.name } }
            if !movable.isEmpty {
                let item = NSMenuItem(title: "Move Tag Here", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for t in movable.prefix(40) {
                    sub.addItem(ClosureMenuItem(t.name) { m.sheet = .editTag(t.name, target: commit.id) })
                }
                item.submenu = sub
                menu.addItem(item)
            }
            menu.addItem(.separator())
            if let current {
                menu.addItem(ClosureMenuItem("Reset \(current) to This Commit") { m.sheet = .reset(commit.id) })
            }
            menu.addItem(ClosureMenuItem("Revert Commit") { m.revert(commit) })
            menu.addItem(ClosureMenuItem("Cherry-Pick") { m.cherryPick(commit) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Copy SHA") { m.copyToPasteboard(commit.id) })
            menu.addItem(ClosureMenuItem("Copy Short SHA") { m.copyToPasteboard(commit.shortHash) })
            menu.addItem(ClosureMenuItem("Copy Message") { m.copyToPasteboard(commit.subject) })

            let deletable = localRefs.filter { !$0.isCurrent }
            if !deletable.isEmpty || !remoteRefs.isEmpty {
                menu.addItem(.separator())
                for ref in deletable {
                    if let b = m.localBranches.first(where: { $0.name == ref.name }) {
                        menu.addItem(ClosureMenuItem("Delete \(ref.name)") { m.deleteBranch(b) })
                    }
                }
                for ref in remoteRefs {
                    if let b = m.remoteBranches.first(where: { $0.name == ref.name }) {
                        menu.addItem(ClosureMenuItem("Delete \(ref.name) on Remote") { m.deleteBranch(b) })
                    }
                }
            }
        }
    }
}

/// Commit rows are clickable: show the pointing hand over them.
final class PointingTableView: NSTableView {
    override func resetCursorRects() {
        let rows = rect(ofRow: max(numberOfRows - 1, 0)).maxY
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: min(rows, bounds.height)), cursor: .pointingHand)
    }
}

// MARK: - Row & cells

final class HistoryRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            for view in subviews { view.needsDisplay = true }   // the graph dot fills white when selected
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Theme.nsSelection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 0), xRadius: 6, yRadius: 6).fill()
    }
}

final class TextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    convenience init(monospaced: Bool) {
        self.init(frame: .zero)
        label.font = monospaced ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
        label.textColor = monospaced ? Theme.nsTertiaryText : Theme.nsSecondaryText
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func set(_ text: String, tooltip: String? = nil) {
        label.stringValue = text
        toolTip = tooltip
    }
}

final class GraphCellView: NSTableCellView {
    static let laneWidth: CGFloat = 14
    private var row = GraphRow()
    private var isWorkingCopy = false
    private var dotOnly = false

    override var isFlipped: Bool { true }

    /// While searching, matches are not adjacent commits, so only the coloured dot on its lane is drawn.
    func configure(_ row: GraphRow, commit: Commit, dotOnly: Bool) {
        self.dotOnly = dotOnly
        clipsToBounds = true   // macOS 14+ no longer clips by default; never draw into the description
        self.row = row
        self.isWorkingCopy = commit.isWorkingCopy
        needsDisplay = true
    }

    /// Lanes start 18pt in: 8pt selection inset plus the design's 10pt first-lane offset.
    private func x(_ lane: Int) -> CGFloat { 18 + CGFloat(lane) * Self.laneWidth }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clip(to: bounds.insetBy(dx: 0, dy: -1))
        let h = bounds.height
        let mid = h / 2
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)

        for line in row.lines where !dotOnly {
            let y0: CGFloat = line.upper ? 0 : mid
            let y1: CGFloat = line.upper ? mid : h
            let x0 = x(line.from), x1 = x(line.to)
            let color = isWorkingCopy && line.from == row.node ? Theme.nsTertiaryText : GraphPalette.color(line.color)
            ctx.setStrokeColor(color.cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x0, y: y0))
            if x0 == x1 {
                ctx.addLine(to: CGPoint(x: x1, y: y1))
            } else {
                let dy = y1 - y0
                ctx.addCurve(to: CGPoint(x: x1, y: y1),
                             control1: CGPoint(x: x0, y: y0 + dy * 0.7),
                             control2: CGPoint(x: x1, y: y0 + dy * 0.3))
            }
            ctx.strokePath()
        }

        // 12pt dot with a 2pt lane-coloured ring; the selected commit is filled white.
        let cx = x(row.node)
        let rect = CGRect(x: cx - 6, y: mid - 6, width: 12, height: 12)
        let lane = isWorkingCopy ? Theme.nsTertiaryText : GraphPalette.color(row.color)
        let fill: NSColor = isWorkingCopy ? Theme.nsCanvas : (selected ? .white : lane)
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(lane.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
    }

    private var selected: Bool {
        (superview as? NSTableRowView)?.isSelected ?? false
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { needsDisplay = true }
    }
}

final class DescriptionCellView: NSTableCellView {
    private var commit: Commit?
    private var color = 0
    private var branchInfo: [String: Branch] = [:]

    override var isFlipped: Bool { true }

    func configure(commit: Commit, color: Int, branches: [String: Branch]) {
        clipsToBounds = true
        self.commit = commit
        self.color = color
        var info: [String: Branch] = [:]
        for ref in commit.refs where ref.kind == .localBranch {
            if let b = branches[ref.name] { info[ref.name] = b }
        }
        branchInfo = info
        toolTip = commit.isWorkingCopy ? nil : commit.subject
        needsDisplay = true
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { needsDisplay = true }
    }

    private static let badgeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let subjectFont = NSFont.systemFont(ofSize: 13)

    override func draw(_ dirtyRect: NSRect) {
        guard let commit else { return }
        let h = bounds.height
        var x: CGFloat = 4

        for ref in commit.refs where !(ref.kind == .remoteBranch && ref.name.hasSuffix("/HEAD")) {
            var text = ref.kind == .head ? "HEAD" : ref.name
            if ref.kind == .localBranch, let b = branchInfo[ref.name] {
                if b.ahead > 0 { text += " ↑\(b.ahead)" }
                if b.behind > 0 { text += " ↓\(b.behind)" }
            }
            let (bg, fg) = style(for: ref)
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.badgeFont, .foregroundColor: fg]
            let size = (text as NSString).size(withAttributes: attrs)
            let iconW: CGFloat = ref.kind == .tag ? 12 : 0
            let w = ceil(size.width) + iconW + 12
            guard x + w < bounds.width - 40 else { break }
            let rect = NSRect(x: x, y: ((h - 18) / 2).rounded(), width: w, height: 18)
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            if ref.kind == .tag, let img = Self.tagImage(fg) {
                img.draw(in: NSRect(x: rect.minX + 6, y: rect.midY - 4.5, width: 9, height: 9))
            }
            (text as NSString).draw(at: NSPoint(x: rect.minX + 6 + iconW, y: rect.midY - size.height / 2), withAttributes: attrs)
            x += w + 6
        }

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let textColor = commit.isWorkingCopy ? Theme.nsSecondaryText : Theme.nsText
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.subjectFont, .foregroundColor: textColor, .paragraphStyle: para]
        let font = Self.subjectFont
        let textH = ceil(font.ascender - font.descender + font.leading)
        let rect = NSRect(x: x, y: (h - textH) / 2, width: max(0, bounds.width - x - 6), height: textH)
        (commit.subject as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    private static func tagImage(_ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: "tag.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold).applying(.init(paletteColors: [color])))
    }

    /// Lane-tinted label: soft background in the lane colour with a readable text colour.
    private func style(for ref: RefLabel) -> (NSColor, NSColor) {
        switch ref.kind {
        case .tag, .head:
            return (Theme.dynamic(0x6B655E, 0.10, 0xB0A9A1, 0.16), Theme.nsSoftText)
        case .localBranch, .remoteBranch:
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let lane = GraphPalette.color(color)
            var resolved = lane
            effectiveAppearance.performAsCurrentDrawingAppearance { resolved = lane.usingColorSpace(.sRGB) ?? lane }
            return (resolved.withAlphaComponent(isDark ? 0.2 : 0.1), GraphPalette.labelColor(color))
        }
    }
}

/// Column header with a solid card background, so rows never shine through while scrolling.
final class OpaqueHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.nsSidebar.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
        Theme.nsBorder.setFill()
        NSRect(x: dirtyRect.minX, y: bounds.maxY - 1, width: dirtyRect.width, height: 1).fill()
    }

    override var isOpaque: Bool { true }
}

/// Column title in the design's small semibold style, without native separators.
final class HistoryHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: Theme.nsSecondaryText,
            .kern: 0.44
        ]
        let size = (stringValue as NSString).size(withAttributes: attrs)
        let leading: CGFloat = controlView is NSTableHeaderView && cellFrame.minX < 1 ? 18 : 6
        (stringValue as NSString).draw(at: NSPoint(x: cellFrame.minX + leading, y: cellFrame.midY - size.height / 2), withAttributes: attrs)
    }
}
