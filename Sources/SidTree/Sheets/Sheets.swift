import SwiftUI

struct SheetHost: View {
    let model: RepoModel
    let kind: SheetKind

    var body: some View {
        Group {
            switch kind {
            case .push: PushSheet(model: model)
            case .pull: PullSheet(model: model)
            case .newBranch(let start): NewBranchSheet(model: model, startPoint: start)
            case .deleteBranches: DeleteBranchesSheet(model: model)
            case .renameBranch(let name): RenameBranchSheet(model: model, oldName: name)
            case .merge(let ref): MergeSheet(model: model, preselected: ref)
            case .rebase(let ref): RebaseSheet(model: model, onto: ref)
            case .stash: StashSheet(model: model)
            case .tag(let commit): TagSheet(model: model, commit: commit)
            case .reset(let commit): ResetSheet(model: model, commit: commit)
            }
        }
        .tint(Theme.accent)
    }
}

/// Shared chrome for all sheets.
struct SheetContainer<Content: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    let confirmTitle: String
    var confirmEnabled = true
    var destructive = false
    var width: CGFloat = 520
    let onConfirm: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondaryText) }
                }
            }
            .padding(20)

            Rectangle().fill(Theme.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 14) { content }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Theme.border).frame(height: 1)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    dismiss()
                    onConfirm()
                }
                .buttonStyle(PillButtonStyle(prominent: true, destructive: destructive))
                .keyboardShortcut(.defaultAction)
                .disabled(!confirmEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.subtle)
        }
        .frame(width: width)
        .background(Theme.card)
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondaryText)
    }
}

struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

private func sanitizeBranchName(_ s: String) -> String {
    s.replacingOccurrences(of: " ", with: "-")
}

// MARK: - Push

struct PushSheet: View {
    let model: RepoModel
    @State private var remote = ""
    @State private var rows: [PushRow] = []
    @State private var pushTags = false
    @State private var force = false

    struct PushRow: Identifiable {
        var id: String { local }
        let local: String
        var remoteName: String
        var include: Bool
        let hasUpstream: Bool
        var track: Bool
    }

    var body: some View {
        SheetContainer(symbol: "arrow.up.circle", title: "Push", subtitle: "Push local branches to a remote",
                       confirmTitle: "Push", confirmEnabled: rows.contains { $0.include } && !remote.isEmpty, width: 620,
                       onConfirm: push) {
            HStack {
                FieldLabel(text: "Push to repository")
                Picker("", selection: $remote) {
                    ForEach(model.remotes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            VStack(spacing: 0) {
                HStack {
                    Text("Push?").frame(width: 50, alignment: .leading)
                    Text("Local branch").frame(maxWidth: .infinity, alignment: .leading)
                    Text("→").frame(width: 20)
                    Text("Remote branch").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Track").frame(width: 46)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Theme.subtle)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($rows) { $row in
                            HStack {
                                Toggle("", isOn: $row.include).labelsHidden().toggleStyle(.checkbox).frame(width: 50, alignment: .leading)
                                HStack(spacing: 5) {
                                    if row.local == model.currentBranch {
                                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                    }
                                    Text(row.local).font(.system(size: 12.5, weight: row.local == model.currentBranch ? .semibold : .regular))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.secondaryText).frame(width: 20)
                                TextField("", text: $row.remoteName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity)
                                Toggle("", isOn: $row.track).labelsHidden().toggleStyle(.checkbox).frame(width: 46)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            Rectangle().fill(Theme.border).frame(height: 1)
                        }
                    }
                }
                .frame(height: min(CGFloat(rows.count) * 35 + 4, 260))
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

            HStack(spacing: 18) {
                Toggle("Push all tags", isOn: $pushTags).toggleStyle(.checkbox)
                Toggle("Force push (with lease)", isOn: $force).toggleStyle(.checkbox)
            }
            .font(.system(size: 12))
        }
        .onAppear(perform: setup)
        .onChange(of: remote) { _, _ in updateRemoteNames() }
    }

    private func setup() {
        let upstreamRemote = RepoModel.splitUpstream(model.currentBranchInfo?.upstream)?.0
        remote = upstreamRemote ?? model.remotes.first ?? ""
        rows = model.localBranches.map { b in
            let up = RepoModel.splitUpstream(b.upstream)
            return PushRow(local: b.name, remoteName: up?.1 ?? b.name, include: b.isHead, hasUpstream: b.upstream != nil, track: b.upstream == nil)
        }
        rows.sort { a, b in (a.local == model.currentBranch) && (b.local != model.currentBranch) }
    }

    private func updateRemoteNames() {
        for i in rows.indices {
            if let b = model.localBranches.first(where: { $0.name == rows[i].local }),
               let up = RepoModel.splitUpstream(b.upstream), up.0 == remote {
                rows[i].remoteName = up.1
            }
        }
    }

    private func push() {
        let selected = rows.filter { $0.include }
        let specs = selected.map { GitService.PushSpec(local: $0.local, remote: $0.remoteName.isEmpty ? $0.local : $0.remoteName) }
        let track = selected.contains { $0.track }
        let remote = self.remote, tags = pushTags, force = self.force
        let target = selected.count == 1 ? "\(remote)/\(specs[0].remote)" : remote
        model.perform("Pushing to \(remote)…", success: "Pushed to \(target)") {
            try await model.git.push(remote: remote, specs: specs, setUpstream: track, tags: tags, force: force)
        }
    }
}

// MARK: - Pull

struct PullSheet: View {
    let model: RepoModel
    @State private var remote = ""
    @State private var branch = ""
    @State private var rebase = false
    @State private var commit = true

    var body: some View {
        SheetContainer(symbol: "arrow.down.circle", title: "Pull",
                       subtitle: "Into \(model.currentBranch ?? "HEAD")", confirmTitle: "Pull",
                       confirmEnabled: !remote.isEmpty && !branch.isEmpty, onConfirm: pull) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    FieldLabel(text: "Pull from repository")
                    Picker("", selection: $remote) { ForEach(model.remotes, id: \.self) { Text($0).tag($0) } }
                        .labelsHidden()
                }
                GridRow {
                    FieldLabel(text: "Remote branch to pull")
                    Picker("", selection: $branch) {
                        ForEach(model.remoteBranches.filter { $0.remoteName == remote }) { Text($0.shortName).tag($0.shortName) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    FieldLabel(text: "Pull into local branch")
                    Text(model.currentBranch ?? "(detached HEAD)").font(.system(size: 13, weight: .medium))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Commit merged changes immediately", isOn: $commit).disabled(rebase)
                Toggle("Rebase instead of merge", isOn: $rebase)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        .onAppear {
            if let up = RepoModel.splitUpstream(model.currentBranchInfo?.upstream) {
                remote = up.0
                branch = up.1
            } else {
                remote = model.remotes.first ?? ""
                branch = model.currentBranch ?? ""
            }
        }
    }

    private func pull() {
        let remote = self.remote, branch = self.branch, rebase = self.rebase, commit = self.commit
        model.perform("Pulling from \(remote)/\(branch)…", success: "Pulled \(remote)/\(branch)") {
            try await model.git.pull(remote: remote, branch: branch, rebase: rebase, commit: commit)
        }
    }
}

// MARK: - Branches

struct NewBranchSheet: View {
    let model: RepoModel
    let startPoint: String?
    @State private var name = ""
    @State private var useStart = false
    @State private var start = ""
    @State private var checkout = true

    var body: some View {
        SheetContainer(symbol: "arrow.triangle.branch", title: "New Branch",
                       subtitle: "Current branch: \(model.currentBranch ?? "detached HEAD")",
                       confirmTitle: "Create Branch", confirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                       onConfirm: create) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Branch name")
                StyledTextField(placeholder: "feature/my-change", text: $name)
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Start from")
                Picker("", selection: $useStart) {
                    Text("Working copy parent").tag(false)
                    Text("Specified commit / branch").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if useStart {
                    StyledTextField(placeholder: "commit hash or branch", text: $start)
                }
            }
            Toggle("Checkout new branch", isOn: $checkout).toggleStyle(.checkbox).font(.system(size: 12))
            Button("Delete branches…") { model.sheet = .deleteBranches }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
        .onAppear {
            if let startPoint {
                useStart = true
                start = startPoint
            }
        }
    }

    private func create() {
        let n = sanitizeBranchName(name.trimmingCharacters(in: .whitespaces))
        let s = useStart && !start.isEmpty ? start : nil
        let co = checkout
        model.perform("Creating \(n)…", success: co ? "Switched to new branch \(n)" : "Created \(n)") {
            try await model.git.createBranch(n, from: s, checkout: co)
        }
    }
}

struct DeleteBranchesSheet: View {
    let model: RepoModel
    @State private var selected: Set<String> = []
    @State private var force = false
    @State private var deleteRemote = false

    var body: some View {
        SheetContainer(symbol: "trash", title: "Delete Branches", subtitle: "Select local branches to delete",
                       confirmTitle: "Delete \(selected.count) Branch\(selected.count == 1 ? "" : "es")",
                       confirmEnabled: !selected.isEmpty, destructive: true, onConfirm: delete) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.localBranches.filter { !$0.isHead }) { b in
                        HStack {
                            Toggle(isOn: Binding(get: { selected.contains(b.name) },
                                                 set: { if $0 { selected.insert(b.name) } else { selected.remove(b.name) } })) {
                                Text(b.name).font(.system(size: 12.5))
                            }
                            .toggleStyle(.checkbox)
                            Spacer()
                            if let up = b.upstream { Text(up).font(.system(size: 11)).foregroundStyle(Theme.secondaryText) }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
            .frame(height: 220)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Force delete regardless of merge status", isOn: $force)
                Toggle("Also delete the tracked remote branches", isOn: $deleteRemote)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
    }

    private func delete() {
        let branches = model.localBranches.filter { selected.contains($0.name) }
        let force = self.force, deleteRemote = self.deleteRemote
        model.perform("Deleting branches…", success: "Deleted \(branches.count) branch\(branches.count == 1 ? "" : "es")") {
            for b in branches {
                try await model.git.deleteBranch(b.name, force: force)
                if deleteRemote, let up = RepoModel.splitUpstream(b.upstream) {
                    try await model.git.deleteRemoteBranch(remote: up.0, name: up.1)
                }
            }
        }
    }
}

struct RenameBranchSheet: View {
    let model: RepoModel
    let oldName: String
    @State private var name = ""

    var body: some View {
        SheetContainer(symbol: "pencil", title: "Rename Branch", subtitle: oldName, confirmTitle: "Rename",
                       confirmEnabled: !name.isEmpty && name != oldName, onConfirm: {
            let n = sanitizeBranchName(name)
            model.perform("Renaming…", success: "Renamed to \(n)") { try await model.git.renameBranch(oldName, to: n) }
        }) {
            StyledTextField(placeholder: "New name", text: $name)
        }
        .onAppear { name = oldName }
    }
}

// MARK: - Merge / rebase

struct MergeSheet: View {
    let model: RepoModel
    let preselected: String?
    @State private var target = ""
    @State private var query = ""
    @State private var commit = true
    @State private var noFF = false
    @State private var squash = false

    private var candidates: [String] {
        let all = model.localBranches.filter { !$0.isHead }.map(\.name) + model.remoteBranches.map(\.name)
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        SheetContainer(symbol: "arrow.triangle.merge", title: "Merge",
                       subtitle: "Merge into \(model.currentBranch ?? "HEAD")", confirmTitle: "Merge",
                       confirmEnabled: !target.isEmpty, width: 560, onConfirm: merge) {
            SearchField(placeholder: "Find branch", text: $query, width: nil)
            ScrollView {
                LazyVStack(spacing: 1) {
                    if let preselected, !candidates.contains(preselected) {
                        branchOption(preselected, label: preselected.count == 40 ? "Commit \(preselected.prefix(8))" : preselected)
                    }
                    ForEach(candidates, id: \.self) { name in branchOption(name, label: name) }
                }
                .padding(4)
            }
            .frame(height: 220)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Commit merged changes immediately", isOn: $commit).disabled(squash)
                Toggle("Create a new commit even if fast-forward is possible", isOn: $noFF).disabled(squash)
                Toggle("Squash commits", isOn: $squash)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        .onAppear { target = preselected ?? "" }
    }

    private func branchOption(_ name: String, label: String) -> some View {
        let selected = target == name
        return HStack(spacing: 8) {
            Image(systemName: name.contains("/") && model.remoteBranches.contains { $0.name == name } ? "cloud" : "arrow.triangle.branch")
                .font(.system(size: 11)).foregroundStyle(selected ? Theme.accent : Theme.secondaryText).frame(width: 16)
            Text(label).font(.system(size: 12.5, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? Theme.accent : Theme.text)
            Spacer()
            if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent) }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.selection : .clear))
        .contentShape(Rectangle())
        .onTapGesture { target = name }
    }

    private func merge() {
        let t = target, noFF = self.noFF, commit = self.commit, squash = self.squash
        model.perform("Merging \(t)…", success: "Merged \(t)") {
            try await model.git.merge(t, noFF: noFF, commit: commit, squash: squash)
        }
    }
}

struct RebaseSheet: View {
    let model: RepoModel
    let onto: String

    var body: some View {
        SheetContainer(symbol: "arrow.triangle.pull", title: "Rebase",
                       subtitle: "Rebase \(model.currentBranch ?? "HEAD") onto \(onto)", confirmTitle: "Rebase",
                       onConfirm: {
            model.perform("Rebasing…", success: "Rebased onto \(onto)") { try await model.git.rebase(onto: onto) }
        }) {
            Text("Your local commits on \(model.currentBranch ?? "HEAD") will be replayed on top of \(onto). Do not rebase commits that others already pulled.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Stash

struct StashSheet: View {
    let model: RepoModel
    @State private var message = ""
    @State private var keepIndex = false
    @State private var untracked = true

    var body: some View {
        SheetContainer(symbol: "tray.and.arrow.down", title: "Stash Changes",
                       subtitle: "\(model.changeCount) changed files", confirmTitle: "Stash", onConfirm: {
            let m = message, k = keepIndex, u = untracked
            model.perform("Stashing…", success: "Changes stashed") { try await model.git.stash(message: m, keepIndex: k, includeUntracked: u) }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Message")
                StyledTextField(placeholder: "Optional description", text: $message)
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Keep staged changes", isOn: $keepIndex)
                Toggle("Include untracked files", isOn: $untracked)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
    }
}

// MARK: - Tag

struct TagSheet: View {
    let model: RepoModel
    let commit: String?
    @State private var name = ""
    @State private var message = ""
    @State private var push = false

    var body: some View {
        SheetContainer(symbol: "tag", title: "New Tag",
                       subtitle: commit.map { "On commit \($0.prefix(8))" } ?? "On working copy parent (HEAD)",
                       confirmTitle: "Add Tag", confirmEnabled: !name.isEmpty, onConfirm: create) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Tag name")
                StyledTextField(placeholder: "v1.0.0", text: $name)
            }
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: "Message (makes an annotated tag)")
                StyledTextField(placeholder: "Optional", text: $message)
            }
            Toggle("Push tag to \(model.remotes.first ?? "origin")", isOn: $push)
                .toggleStyle(.checkbox).font(.system(size: 12))
                .disabled(model.remotes.isEmpty)
        }
    }

    private func create() {
        let n = name.replacingOccurrences(of: " ", with: "-"), m = message, p = push
        let target = commit ?? "HEAD"
        let remote = model.remotes.first ?? "origin"
        model.perform("Creating tag…", success: "Tagged \(n)") {
            try await model.git.createTag(n, at: target, message: m)
            if p { try await model.git.pushTag(n, remote: remote) }
        }
    }
}

// MARK: - Reset

struct ResetSheet: View {
    let model: RepoModel
    let commit: String
    @State private var mode: ResetMode = .mixed

    var body: some View {
        SheetContainer(symbol: "arrow.uturn.backward", title: "Reset \(model.currentBranch ?? "HEAD")",
                       subtitle: "To commit \(commit.prefix(8))", confirmTitle: "Reset",
                       destructive: mode == .hard, onConfirm: {
            let m = mode
            model.perform("Resetting…", success: "Reset to \(commit.prefix(8))") { try await model.git.reset(to: commit, mode: m) }
        }) {
            Picker("", selection: $mode) {
                ForEach(ResetMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if mode == .hard {
                Label("All uncommitted changes will be lost permanently.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.red)
            }
        }
    }
}
