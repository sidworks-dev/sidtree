import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: RepoModel
    @AppStorage("sidebar.v2.branches") private var branchesExpanded = true
    @AppStorage("sidebar.v2.more") private var moreExpanded = true
    @AppStorage("sidebar.v2.remotes") private var remotesExpanded = false
    @AppStorage("sidebar.v2.tags") private var tagsExpanded = false
    @AppStorage("sidebar.v2.stashes") private var stashesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 2) {
                    NavRow(symbol: "dot.square", title: "Changes", badge: model.changeCount,
                           selected: model.sidebarSelection == .changes) {
                        model.sidebarSelection = .changes
                    }
                    .help("Changes (⌘1)")
                    NavRow(symbol: "clock", title: "History", badge: 0,
                           selected: model.showsHistory) {
                        model.sidebarSelection = .history
                    }
                    .help("History (⌘2)")
                }

                SectionHeader(title: "Branches", itemCount: model.localBranches.count, expanded: $branchesExpanded)
                if branchesExpanded {
                    SearchField(placeholder: "Filter branches", text: $model.sidebarFilter, width: nil, height: 27)
                        .padding(.bottom, 6)
                    VStack(spacing: 1) {
                        ForEach(filtered(model.localBranches)) { branch in
                            branchRow(branch)
                        }
                        if filtered(model.localBranches).isEmpty {
                            EmptyRow(text: model.sidebarFilter.isEmpty ? "No branches" : "No matching branches")
                        }
                    }
                }

                SectionHeader(title: "More", itemCount: 0, expanded: $moreExpanded)
                if moreExpanded {
                    VStack(spacing: 1) {
                        GroupRow(symbol: "cloud", title: "Remotes", count: model.remotes.count, expanded: $remotesExpanded)
                        if remotesExpanded { remotesList }
                        GroupRow(symbol: "tag", title: "Tags", count: model.tags.count, expanded: $tagsExpanded)
                        if tagsExpanded { tagsList }
                        GroupRow(symbol: "archivebox", title: "Stashes", count: model.stashes.count, expanded: $stashesExpanded)
                        if stashesExpanded { stashesList }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: Pieces

    private func branchRow(_ branch: Branch) -> some View {
        let selected = model.sidebarSelection == .branch(branch.name)
        return SidebarRow(selected: selected, current: branch.isHead) {
            model.sidebarSelection = .branch(branch.name)
        } doubleTap: {
            model.checkout(branch: branch)
        } content: {
            Image(systemName: branch.isHead ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: branch.isHead ? 12 : 11, weight: .medium))
                .foregroundStyle(branch.isHead ? Theme.action : Theme.tertiaryText)
                .frame(width: 16)
            Text(branch.name)
                .font(.system(size: 13, weight: branch.isHead ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                if model.pushingBranches.contains(branch.name) {
                    ProgressView().controlSize(.mini).frame(width: 12, height: 12).help("Pushing…")
                }
                if branch.upstreamGone {
                    Image(systemName: "icloud.slash").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
                        .help("Upstream branch is gone")
                }
                if branch.ahead > 0 { Text("↑\(branch.ahead)").foregroundStyle(Theme.accent) }
                if branch.behind > 0 { Text("↓\(branch.behind)").foregroundStyle(Theme.orange) }
                if branch.isHead && branch.ahead == 0 && branch.behind == 0 {
                    Text("current").foregroundStyle(Theme.tertiaryText)
                }
            }
            .font(.system(size: 11).monospacedDigit())
        }
        .help(branch.upstream.map { "Tracking \($0) · double-click to checkout" } ?? "No upstream · double-click to checkout")
        .contextMenu { branchMenu(branch) }
    }

    @ViewBuilder
    private var remotesList: some View {
        if model.remotes.isEmpty {
            EmptyRow(text: "No remotes")
        }
        ForEach(model.remotes, id: \.self) { remote in
            SubRow(symbol: "cloud", title: remote, monospaced: false, selected: false, tap: {}, doubleTap: {})
                .contextMenu {
                    Button("Fetch \(remote)") { model.fetch() }
                    Button("Copy Remote Name") { model.copyToPasteboard(remote) }
                }
            ForEach(filtered(model.remoteBranches.filter { $0.remoteName == remote && !$0.name.hasSuffix("/HEAD") })) { branch in
                SubRow(symbol: "arrow.triangle.branch", title: branch.shortName, monospaced: false,
                       selected: model.sidebarSelection == .remoteBranch(branch.name), indent: 22) {
                    model.sidebarSelection = .remoteBranch(branch.name)
                } doubleTap: {
                    model.checkout(branch: branch)
                }
                .help("Double-click to checkout")
                .contextMenu { remoteBranchMenu(branch) }
            }
        }
    }

    @ViewBuilder
    private var tagsList: some View {
        let tags = model.tags.filter { matches($0.name) }
        if tags.isEmpty { EmptyRow(text: model.tags.isEmpty ? "No tags" : "No matching tags") }
        ForEach(tags) { tag in
            SubRow(symbol: "tag", title: tag.name, monospaced: false, selected: model.sidebarSelection == .tag(tag.name)) {
                model.sidebarSelection = .tag(tag.name)
            } doubleTap: {
                model.checkoutDetached(tag.hash)
            }
            .contextMenu { tagMenu(tag) }
        }
    }

    @ViewBuilder
    private var stashesList: some View {
        if model.stashes.isEmpty { EmptyRow(text: "No stashes") }
        ForEach(model.stashes) { stash in
            SubRow(symbol: "archivebox", title: stash.message, monospaced: false, selected: model.sidebarSelection == .stash(stash.ref)) {
                model.sidebarSelection = .stash(stash.ref)
            } doubleTap: {
                model.applyStash(stash, pop: false)
            }
            .help("\(stash.ref) · \(stash.date.formatted(date: .abbreviated, time: .shortened))")
            .contextMenu { stashMenu(stash) }
        }
    }

    private func matches(_ name: String) -> Bool {
        model.sidebarFilter.isEmpty || name.localizedCaseInsensitiveContains(model.sidebarFilter)
    }

    private func filtered(_ branches: [Branch]) -> [Branch] { branches.filter { matches($0.name) } }

    // MARK: Menus

    @ViewBuilder
    private func branchMenu(_ b: Branch) -> some View {
        Button("Checkout \(b.name)") { model.checkout(branch: b) }.disabled(b.isHead)
        if let current = model.currentBranch, !b.isHead {
            Button("Merge \(b.name) into \(current)") { model.sheet = .merge(b.name) }
            Button("Rebase \(current) onto \(b.name)") { model.sheet = .rebase(b.name) }
        }
        Divider()
        Button("New Branch from \(b.name)") { model.sheet = .newBranch(startPoint: b.name) }
        Button("Rename") { model.sheet = .renameBranch(b.name) }
        if b.isHead { Button("Push to") { model.sheet = .push } }
        Divider()
        Button("Copy Branch Name") { model.copyToPasteboard(b.name) }
        Divider()
        Button("Delete \(b.name)…", role: .destructive) { model.deleteBranch(b) }.disabled(b.isHead)
    }

    @ViewBuilder
    private func remoteBranchMenu(_ b: Branch) -> some View {
        Button("Checkout \(b.name)") { model.checkout(branch: b) }
        if let current = model.currentBranch {
            Button("Merge \(b.name) into \(current)") { model.sheet = .merge(b.name) }
            Button("Rebase \(current) onto \(b.name)") { model.sheet = .rebase(b.name) }
        }
        Button("New Branch from \(b.name)") { model.sheet = .newBranch(startPoint: b.name) }
        Divider()
        Button("Copy Branch Name") { model.copyToPasteboard(b.name) }
        Divider()
        Button("Delete \(b.shortName) on \(b.remoteName ?? "remote")…", role: .destructive) { model.deleteBranch(b) }
    }

    @ViewBuilder
    private func tagMenu(_ t: Tag) -> some View {
        Button("Checkout \(t.name)") { model.checkoutDetached(t.hash) }
        Button("Push Tag to \(model.remotes.first ?? "origin")") {
            let remote = model.remotes.first ?? "origin"
            model.perform("Pushing tag…", success: "Pushed \(t.name)") { try await model.git.pushTag(t.name, remote: remote) }
        }
        Button("Copy Tag Name") { model.copyToPasteboard(t.name) }
        Divider()
        Button("Edit Tag") { model.sheet = .editTag(t.name, target: nil) }
        Button("Delete Tag", role: .destructive) { model.deleteTag(t) }
    }

    @ViewBuilder
    private func stashMenu(_ s: Stash) -> some View {
        Button("Apply Stash") { model.applyStash(s, pop: false) }
        Button("Pop Stash") { model.applyStash(s, pop: true) }
        Divider()
        Button("Delete Stash…", role: .destructive) { model.dropStash(s) }
    }
}

// MARK: - Rows

struct NavRow: View {
    let symbol: String
    let title: String
    let badge: Int
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 13, weight: .regular))
                    .frame(width: 16, height: 16)
                    .opacity(0.85)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 17)
                        .background(Capsule().fill(Theme.action))
                }
            }
            .foregroundStyle(selected ? Theme.text : Theme.softText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Theme.navSelected : (hover ? Theme.subtle : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
    }
}

/// A clickable sidebar row: single click selects, double click runs the default action.
struct SidebarRow<Content: View>: View {
    let selected: Bool
    var current = false
    let tap: () -> Void
    let doubleTap: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false

    var body: some View {
        HStack(spacing: 9) { content }
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .handCursor()
            .onTapGesture(count: 2) { doubleTap() }
            .simultaneousGesture(TapGesture().onEnded { tap() })
    }

    private var fill: Color {
        if selected { return Theme.selection }
        if current { return Theme.currentRow }
        return hover ? Theme.subtle : .clear
    }
}

/// Indented item under Remotes, Tags or Stashes.
private struct SubRow: View {
    let symbol: String
    let title: String
    let monospaced: Bool
    let selected: Bool
    var indent: CGFloat = 8
    let tap: () -> Void
    let doubleTap: () -> Void

    var body: some View {
        SidebarRow(selected: selected, tap: tap, doubleTap: doubleTap) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Theme.accent : Theme.tertiaryText)
                .frame(width: 16)
            Text(title)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12.5))
                .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(title)
            Spacer(minLength: 0)
        }
        .padding(.leading, indent)
    }
}

private struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 35)
            .padding(.vertical, 5)
    }
}

/// "Remotes 1 ›" row that expands its items.
private struct GroupRow: View {
    let symbol: String
    let title: String
    let count: Int
    @Binding var expanded: Bool
    @State private var hover = false

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12, weight: .regular)).foregroundStyle(Theme.secondaryText).frame(width: 16)
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.softText)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.tertiaryText)
                Chevron(expanded: expanded).foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Theme.subtle : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
    }
}

private struct Chevron: View {
    let expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9.5, weight: .semibold))
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(width: 14, height: 14)
    }
}

struct SectionHeader: View {
    let title: String
    let itemCount: Int
    @Binding var expanded: Bool
    @State private var hover = false

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.66)
                if itemCount > 0 {
                    SectionCount(text: "\(itemCount)").padding(.leading, 4)
                }
                Spacer()
                Chevron(expanded: expanded)
            }
            .foregroundStyle(hover ? Theme.secondaryText : Theme.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}
