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
        let table = NSTableView()
        table.style = .fullWidth
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.backgroundColor = Theme.nsCard

        for (id, title, width, min) in [
            ("graph", "Graph", 120.0, 30.0),
            ("description", "Description", 560.0, 160.0),
            ("date", "Date", 150.0, 80.0),
            ("author", "Author", 150.0, 60.0),
            ("hash", "Commit", 80.0, 50.0)
        ] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = min
            col.resizingMask = .userResizingMask
            table.addTableColumn(col)
        }
        table.autosaveName = "SidTreeHistoryTable"
        table.autosaveTableColumns = true

        let header = OpaqueHeaderView()
        header.frame = NSRect(x: 0, y: 0, width: 100, height: 28)
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

        init(model: RepoModel) { self.model = model }

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
            if filtering {
                col.isHidden = true
                return
            }
            col.isHidden = false
            var lanes = 1
            for row in rows { lanes = max(lanes, row.graph.width) }
            col.width = min(max(CGFloat(lanes) * GraphCellView.laneWidth + 14, 36), 360)
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
                view.configure(item.graph, commit: item.commit, isHead: item.commit.id == model.status.headOID)
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
                    case "date": view.set(Formatters.relativeDate(c.date))
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
                model.sidebarSelection = .fileStatus
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
                menu.addItem(ClosureMenuItem("Show File Status") { [model] in model.sidebarSelection = .fileStatus })
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

// MARK: - Menu helper

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("ClosureMenuItem is created in code only") }

    @objc private func fire() { handler() }
}

// MARK: - Formatters

enum Formatters {
    static let relative: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f
    }()

    static func relativeDate(_ d: Date) -> String { relative.string(from: d) }
}

// MARK: - Row & cells

final class HistoryRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Theme.nsSelection.setFill()
        bounds.fill()
        Theme.nsAccent.setFill()
        NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
    }
}

final class TextCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    convenience init(monospaced: Bool) {
        self.init(frame: .zero)
        label.font = monospaced ? .monospacedSystemFont(ofSize: 11.5, weight: .regular) : .systemFont(ofSize: 12)
        label.textColor = monospaced ? Theme.nsSecondaryText : Theme.nsText
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
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
    private var isHead = false
    private var isWorkingCopy = false
    private var isMerge = false

    override var isFlipped: Bool { true }

    func configure(_ row: GraphRow, commit: Commit, isHead: Bool) {
        clipsToBounds = true   // macOS 14+ no longer clips by default; never draw into the description
        self.row = row
        self.isHead = isHead
        self.isWorkingCopy = commit.isWorkingCopy
        self.isMerge = commit.isMerge
        needsDisplay = true
    }

    private func x(_ lane: Int) -> CGFloat { 12 + CGFloat(lane) * Self.laneWidth }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clip(to: bounds.insetBy(dx: 0, dy: -1))
        let h = bounds.height
        let mid = h / 2
        ctx.setLineWidth(2)
        ctx.setLineCap(.round)

        for line in row.lines {
            let y0: CGFloat = line.upper ? 0 : mid
            let y1: CGFloat = line.upper ? mid : h
            let x0 = x(line.from), x1 = x(line.to)
            let color = isWorkingCopy && line.from == row.node ? NSColor.tertiaryLabelColor : GraphPalette.color(line.color)
            ctx.setStrokeColor(color.cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x0, y: y0))
            if x0 == x1 {
                ctx.addLine(to: CGPoint(x: x1, y: y1))
            } else {
                let dy = y1 - y0
                ctx.addCurve(to: CGPoint(x: x1, y: y1),
                             control1: CGPoint(x: x0, y: y0 + dy * 0.75),
                             control2: CGPoint(x: x1, y: y0 + dy * 0.25))
            }
            ctx.strokePath()
        }

        let cx = x(row.node)
        let color = GraphPalette.color(row.color)
        if isWorkingCopy {
            let r: CGFloat = 5
            let rect = CGRect(x: cx - r, y: mid - r, width: r * 2, height: r * 2)
            ctx.setFillColor(Theme.nsCard.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(Theme.nsSecondaryText.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [2, 2])
            ctx.strokeEllipse(in: rect)
            ctx.setLineDash(phase: 0, lengths: [])
        } else if isHead {
            let r: CGFloat = 5.5
            let rect = CGRect(x: cx - r, y: mid - r, width: r * 2, height: r * 2)
            ctx.setFillColor(Theme.nsCard.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(2.5)
            ctx.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
            let inner: CGFloat = 2
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - inner, y: mid - inner, width: inner * 2, height: inner * 2))
        } else {
            let r: CGFloat = isMerge ? 3.5 : 4.5
            let rect = CGRect(x: cx - r, y: mid - r, width: r * 2, height: r * 2)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(Theme.nsCard.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.25)
            ctx.strokeEllipse(in: rect.insetBy(dx: -0.6, dy: -0.6))
        }
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

    private static let badgeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static var badgeImages: [String: NSImage] = [:]

    private static func badgeImage(_ symbol: String) -> NSImage? {
        if let cached = badgeImages[symbol] { return cached }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold).applying(.init(paletteColors: [.white])))
        badgeImages[symbol] = img
        return img
    }
    private static let subjectFont = NSFont.systemFont(ofSize: 12)
    private static let currentFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    override func draw(_ dirtyRect: NSRect) {
        guard let commit else { return }
        let h = bounds.height
        var x: CGFloat = 6

        for ref in commit.refs {
            let (bg, symbol) = style(for: ref)
            var text = ref.name
            if ref.kind == .localBranch, let b = branchInfo[ref.name] {
                if b.ahead > 0 { text += "  \(b.ahead)↑" }
                if b.behind > 0 { text += "  \(b.behind)↓" }
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.badgeFont, .foregroundColor: NSColor.white]
            let size = (text as NSString).size(withAttributes: attrs)
            let iconW: CGFloat = symbol == nil ? 0 : 13
            let w = ceil(size.width) + iconW + 12
            guard x + w < bounds.width - 40 else { break }
            let rect = NSRect(x: x, y: (h - 17) / 2, width: w, height: 17)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5)
            bg.setFill()
            path.fill()
            if let symbol, let img = Self.badgeImage(symbol) {
                let s = img.size
                img.draw(in: NSRect(x: rect.minX + 6, y: rect.midY - s.height / 2, width: s.width, height: s.height))
            }
            (text as NSString).draw(at: NSPoint(x: rect.minX + 6 + iconW, y: rect.midY - size.height / 2), withAttributes: attrs)
            x += w + 5
        }

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let font: NSFont
        let textColor: NSColor
        if commit.isWorkingCopy {
            font = NSFontManager.shared.convert(Self.currentFont, toHaveTrait: .italicFontMask)
            textColor = Theme.nsSecondaryText
        } else {
            font = commit.refs.contains(where: { $0.isCurrent }) ? Self.currentFont : Self.subjectFont
            textColor = Theme.nsText
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .paragraphStyle: para]
        let textH = ceil(font.ascender - font.descender + font.leading)
        let rect = NSRect(x: x + 2, y: (h - textH) / 2, width: max(0, bounds.width - x - 6), height: textH)
        (commit.subject as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }

    private func style(for ref: RefLabel) -> (NSColor, String?) {
        let lane = GraphPalette.color(color)
        switch ref.kind {
        case .head: return (NSColor.systemGray, "location.fill")
        case .localBranch:
            let background = ref.isCurrent ? lane : lane.blended(withFraction: 0.15, of: .black) ?? lane
            return (background, ref.isCurrent ? "checkmark" : "arrow.triangle.branch")
        case .remoteBranch: return (lane.withAlphaComponent(0.62), "cloud.fill")
        case .tag: return (NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1), "tag.fill")
        }
    }
}

/// Column header with a solid card background, so rows never shine through while scrolling.
final class OpaqueHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.nsCard.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
        Theme.nsBorder.setFill()
        NSRect(x: dirtyRect.minX, y: bounds.maxY - 1, width: dirtyRect.width, height: 1).fill()
    }

    override var isOpaque: Bool { true }
}
