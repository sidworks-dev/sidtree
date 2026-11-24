import AppKit
import SwiftUI

enum AppInfo {
    static let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    static let logo: NSImage? = Bundle.main.image(forResource: "sidworks-logo")
}

struct LogoMark: View {
    var size: CGFloat = 30
    var body: some View {
        if let logo = AppInfo.logo {
            Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                .frame(width: size * 0.62, height: size * 0.82)
                .frame(width: size, height: size)
                .background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        } else {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        }
    }
}

struct SidebarView: View {
    @Bindable var model: RepoModel
    let switchRepo: (URL?) -> Void
    @AppStorage("sidebar.branches") private var branchesExpanded = true
    @AppStorage("sidebar.tags") private var tagsExpanded = false
    @AppStorage("sidebar.remotes") private var remotesExpanded = true
    @AppStorage("sidebar.stashes") private var stashesExpanded = true
    @State private var expandedRemotes: Set<String> = []
    @ObservedObject private var recent = RecentRepos.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    NavRow(symbol: "square.and.pencil", title: "File Status", badge: model.changeCount,
                           selected: model.sidebarSelection == .fileStatus) {
                        model.sidebarSelection = .fileStatus
                    }
                    NavRow(symbol: "clock.arrow.circlepath", title: "History", badge: 0,
                           selected: model.sidebarSelection == .history) {
                        model.sidebarSelection = .history
                    }

                    SectionHeader(title: "Branches", count: model.localBranches.count, expanded: $branchesExpanded)
                    if branchesExpanded {
                        ForEach(filtered(model.localBranches)) { branch in
                            branchRow(branch)
                        }
                    }

                    SectionHeader(title: "Remotes", count: model.remotes.count, expanded: $remotesExpanded)
                    if remotesExpanded {
                        ForEach(model.remotes, id: \.self) { remote in
                            remoteSection(remote)
                        }
                    }

                    SectionHeader(title: "Tags", count: model.tags.count, expanded: $tagsExpanded)
                    if tagsExpanded {
                        ForEach(model.tags.filter { matches($0.name) }) { tag in
                            ItemRow(symbol: "tag", title: tag.name, selected: model.sidebarSelection == .tag(tag.name)) {
                                model.sidebarSelection = .tag(tag.name)
                            } doubleTap: {
                                model.checkoutDetached(tag.hash)
                            }
                            .contextMenu { tagMenu(tag) }
                        }
                    }

                    SectionHeader(title: "Stashes", count: model.stashes.count, expanded: $stashesExpanded)
                    if stashesExpanded {
                        ForEach(model.stashes) { stash in
                            ItemRow(symbol: "tray.full", title: stash.message, selected: model.sidebarSelection == .stash(stash.ref)) {
                                model.sidebarSelection = .stash(stash.ref)
                            } doubleTap: {
                                model.applyStash(stash, pop: false)
                            }
                            .help("\(stash.ref) · \(stash.date.formatted(date: .abbreviated, time: .shortened))")
                            .contextMenu { stashMenu(stash) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }

            VStack(spacing: 8) {
                SearchField(placeholder: "Filter branches", text: $model.sidebarFilter, width: nil)
                repoSwitcher
            }
            .padding(10)
        }
        .onAppear { expandFirstRemote(model.remotes) }
        .onChange(of: model.remotes) { _, remotes in expandFirstRemote(remotes) }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("SidTree").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(AppInfo.version).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            UpdateBadge()
        }
        .padding(.horizontal, 16)
        .padding(.top, 38)    // room for the traffic lights
        .padding(.bottom, 12)
        .background(WindowDragArea())
    }

    private var repoSwitcher: some View {
        Button(action: showRepoMenu) {
            HStack(spacing: 9) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text((model.root.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            }
            .padding(8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch repository")
    }

    private func showRepoMenu() {
        let menu = NSMenu()
        for url in recent.urls where url != model.root {
            let item = ClosureMenuItem(url.lastPathComponent) { switchRepo(url) }
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(item)
        }
        if menu.items.count > 0 { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem("Open Repository") {
            if let url = RepoPicker.choose() { switchRepo(url) }
        })
        menu.addItem(ClosureMenuItem("Close Repository") { switchRepo(nil) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func branchRow(_ branch: Branch) -> some View {
        let selected = model.sidebarSelection == .branch(branch.name)
        return ItemRow(symbol: branch.isHead ? "checkmark.circle.fill" : "arrow.triangle.branch",
                       title: branch.name, selected: selected, emphasized: branch.isHead) {
            model.sidebarSelection = .branch(branch.name)
        } doubleTap: {
            model.checkout(branch: branch)
        } trailing: {
            HStack(spacing: 3) {
                if branch.upstreamGone {
                    Image(systemName: "icloud.slash").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                        .help("Upstream branch is gone")
                }
                if branch.ahead > 0 { SoftBadge(text: "\(branch.ahead)↑", color: Theme.accent, background: Theme.violetSoft) }
                if branch.behind > 0 { SoftBadge(text: "\(branch.behind)↓", color: Theme.orange, background: Theme.orangeSoft) }
            }
        }
        .help(branch.upstream.map { "Tracking \($0) · double-click to checkout" } ?? "No upstream · double-click to checkout")
        .contextMenu { branchMenu(branch) }
    }

    @ViewBuilder
    private func remoteSection(_ remote: String) -> some View {
        let open = expandedRemotes.contains(remote) || !model.sidebarFilter.isEmpty
        Button {
            if expandedRemotes.contains(remote) { expandedRemotes.remove(remote) } else { expandedRemotes.insert(remote) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 10)
                Image(systemName: "cloud").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                Text(remote).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if open {
            ForEach(filtered(model.remoteBranches.filter { $0.remoteName == remote })) { branch in
                ItemRow(symbol: "arrow.triangle.branch", title: branch.shortName,
                        selected: model.sidebarSelection == .remoteBranch(branch.name)) {
                    model.sidebarSelection = .remoteBranch(branch.name)
                } doubleTap: {
                    model.checkout(branch: branch)
                }
                .padding(.leading, 14)
                .contextMenu { remoteBranchMenu(branch) }
            }
        }
    }

    private func expandFirstRemote(_ remotes: [String]) {
        if expandedRemotes.isEmpty, let first = remotes.first { expandedRemotes.insert(first) }
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
        Button("Delete Tag…", role: .destructive) { model.deleteTag(t) }
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
                Image(systemName: symbol).font(.system(size: 12.5, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accent : Theme.text)
                Spacer()
                if badge > 0 {
                    SoftBadge(text: "\(badge)", color: selected ? .white : Theme.accent, background: selected ? Theme.accent : Theme.violetSoft)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(rowBackground(selected: selected, hover: hover))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

@ViewBuilder
func rowBackground(selected: Bool, hover: Bool) -> some View {
    if selected {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 1.5, y: 1)
    } else if hover {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.subtle)
    } else {
        Color.clear
    }
}

struct ItemRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let selected: Bool
    var emphasized = false
    let tap: () -> Void
    let doubleTap: () -> Void
    @ViewBuilder var trailing: Trailing
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(emphasized || selected ? Theme.accent : Theme.secondaryText)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12.5, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.accent : Theme.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .help(title)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 27)
        .background(rowBackground(selected: selected, hover: hover))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { doubleTap() }
        .simultaneousGesture(TapGesture().onEnded { tap() })
    }
}

extension ItemRow where Trailing == EmptyView {
    init(symbol: String, title: String, selected: Bool, emphasized: Bool = false,
         tap: @escaping () -> Void, doubleTap: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, selected: selected, emphasized: emphasized, tap: tap, doubleTap: doubleTap) { EmptyView() }
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    @Binding var expanded: Bool

    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() } } label: {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                if count > 0 {
                    Text("\(count)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Theme.secondaryText.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
