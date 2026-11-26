import AppKit
import SwiftUI

/// Repository name and path, with the sync and branch actions.
struct RepoToolbar: View {
    let model: RepoModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(DisplayPath.parent(of: model.root))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .help(model.root.path)
            .contextMenu {
                Button("Open in \(model.editorName)") { model.openInEditor() }
                Button("Show in Finder") { model.showInFinder() }
                Button("Open in Terminal") { model.openTerminal() }
                Button("Open Remote in Browser") { model.openRemoteInBrowser() }
                    .disabled(model.remotes.isEmpty)
                Divider()
                Button("Copy Path") { model.copyToPasteboard(model.root.path) }
            }

            if let activity = model.activity {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(activity).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Theme.violetSoft, in: Capsule())
                .transition(.opacity)
            }

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                let fetching = model.syncing.contains(.fetch)
                let pulling = model.syncing.contains(.pull)
                let pushing = model.syncing.contains(.push)
                SegmentButton(title: "Fetch", symbol: "arrow.clockwise", busy: fetching,
                              help: fetching ? "Fetching…" : "Fetch all remotes (⇧⌘F)") { model.fetch() }
                Rectangle().fill(Theme.controlBorder).frame(width: 1)
                SegmentButton(title: "Pull", symbol: "arrow.down", busy: pulling, help: pulling ? "Pulling…" : "Pull (⇧⌘L)",
                              action: { model.sheet = .pull },
                              badge: { CountBadge(count: model.status.behind, fill: Theme.amber, textColor: Theme.onAmber, showsZero: true) })
                    // Nothing to pull: Fetch first to see new commits (Repository → Pull… stays available).
                    .disabled(!pulling && (model.status.behind == 0 || model.remotes.isEmpty))
                Rectangle().fill(Theme.controlBorder).frame(width: 1)
                SegmentButton(title: "Push", symbol: "arrow.up", busy: pushing, help: pushing ? "Pushing…" : "Push (⇧⌘P)",
                              action: { model.sheet = .push },
                              badge: { CountBadge(count: model.status.ahead, showsZero: true) })
                    // A branch that was never pushed has no upstream yet and can always be pushed.
                    .disabled(!pushing && (model.remotes.isEmpty
                                           || (model.status.ahead == 0 && model.currentBranchInfo?.upstream != nil)))
            }
            .frame(height: 30)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 1))
            .fixedSize()

            HStack(spacing: 6) {
                Button { model.sheet = .newBranch(startPoint: nil) } label: { ToolbarLabel(title: "Branch", symbol: "arrow.triangle.branch") }
                    .help("New branch (⇧⌘B)")
                Button { model.sheet = .merge(nil) } label: { ToolbarLabel(title: "Merge", symbol: "arrow.triangle.merge") }
                    .help("Merge into current branch (⇧⌘M)")
                Button { model.sheet = .stash } label: { ToolbarLabel(title: "Stash", symbol: "archivebox") }
                    .disabled(!model.hasLocalChanges)
                    .help("Stash local changes (⇧⌘S)")
            }
            .buttonStyle(PillButtonStyle())
            .fixedSize()

            EditorButton(model: model)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(Theme.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .animation(.easeInOut(duration: 0.15), value: model.activity)
    }
}

/// Opens the repository in the editor chosen in Settings; shows that editor's icon.
private struct EditorButton: View {
    let model: RepoModel
    @AppStorage(EditorSettings.key) private var editorPath = ""

    var body: some View {
        Button { model.openInEditor() } label: {
            if let editor = EditorSettings.current {
                Image(nsImage: editor.icon).resizable().interpolation(.high).frame(width: 18, height: 18)
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(PillButtonStyle())
        .help(editorPath.isEmpty ? "Open in editor: choose one in Settings → Tools" : "Open in \(model.editorName) (⇧⌘E)")
        .id(editorPath)
    }
}

struct ToolbarLabel: View {
    let title: String
    let symbol: String
    /// Shows a small spinner in place of the icon while the action runs.
    var busy = false

    var body: some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView().controlSize(.mini).frame(width: 13, height: 13)
            } else {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium)).opacity(0.85)
            }
            Text(title)
        }
    }
}

/// One part of the Fetch | Pull | Push group.
private struct SegmentButton<Badge: View>: View {
    let title: String
    let symbol: String
    var busy = false
    let help: String
    let action: () -> Void
    @ViewBuilder var badge: Badge
    @State private var hover = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ToolbarLabel(title: title, symbol: symbol, busy: busy)
                badge
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .frame(maxHeight: .infinity)
            .opacity(isEnabled ? 1 : 0.45)
            .background(hover && isEnabled ? Theme.controlHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor(isEnabled)
        .onHover { hover = $0 }
        .help(help)
    }
}

extension SegmentButton where Badge == EmptyView {
    init(title: String, symbol: String, busy: Bool = false, help: String, action: @escaping () -> Void) {
        self.init(title: title, symbol: symbol, busy: busy, help: help, action: action) { EmptyView() }
    }
}
