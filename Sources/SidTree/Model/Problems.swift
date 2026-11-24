import SwiftUI

struct ProblemAction: Identifiable {
    enum Style { case normal, prominent, destructive }
    let id = UUID()
    let title: String
    var style: Style = .normal
    let run: () -> Void
}

/// A failure explained for people: what happened, which files, what to do next, and git's raw output.
struct ProblemReport: Identifiable {
    let id = UUID()
    var symbol = "exclamationmark.triangle.fill"
    var title: String
    var message: String
    var files: [String] = []
    var hint: String?
    var details: String
    var actions: [ProblemAction] = []
}

enum ProblemInterpreter {
    /// - Parameters:
    ///   - retry: re-runs the failed operation.
    ///   - stashAndRetry: stashes local changes (incl. untracked) and re-runs the operation.
    @MainActor
    static func report(for raw: String, label: String, model: RepoModel,
                       retry: (() -> Void)?, stashAndRetry: (() -> Void)?) -> ProblemReport {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let indented = text.components(separatedBy: "\n")
            .filter { $0.hasPrefix("\t") || $0.hasPrefix("    ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let action = label.replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)

        // Local changes would be overwritten (checkout, merge, pull, cherry-pick, stash apply…)
        if lower.contains("would be overwritten by") {
            let untracked = lower.contains("untracked working tree files")
            let what: String = {
                if lower.contains("by checkout") { return "Switching branches" }
                if lower.contains("by merge") { return "This merge" }
                return "This action"
            }()
            var r = ProblemReport(
                symbol: "tray.full.fill",
                title: untracked ? "Untracked files are in the way" : "Your local changes are in the way",
                message: "\(what) would overwrite \(untracked ? "untracked files" : "uncommitted changes") in:",
                files: indented,
                hint: "Stash them to keep them safe. You can restore them later from Stashes in the sidebar.",
                details: text)
            if let stashAndRetry {
                r.actions.append(ProblemAction(title: lower.contains("by checkout") ? "Stash & Switch" : "Stash & Continue",
                                               style: .prominent, run: stashAndRetry))
            }
            return r
        }

        // Merge / rebase / cherry-pick conflicts
        if lower.contains("conflict") && (lower.contains("merge conflict") || lower.contains("automatic merge failed")
                                          || lower.contains("could not apply") || lower.contains("after resolving")) {
            let files = text.components(separatedBy: "\n").compactMap { line -> String? in
                guard let range = line.range(of: "Merge conflict in ") else { return nil }
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return ProblemReport(
                symbol: "arrow.triangle.merge",
                title: "Conflicts need your attention",
                message: files.isEmpty ? "Some files were changed on both sides." : "These files were changed on both sides:",
                files: files,
                hint: "Resolve them in File Status, stage them and commit (or continue the rebase). You can also abort and go back.",
                details: text,
                actions: [
                    ProblemAction(title: "Abort", style: .destructive) { model.abortOperation() },
                    ProblemAction(title: "Resolve Conflicts", style: .prominent) { model.sidebarSelection = .fileStatus },
                ])
        }

        // Push rejected because the remote moved on
        if lower.contains("[rejected]") || lower.contains("non-fast-forward") || lower.contains("fetch first")
            || lower.contains("updates were rejected") {
            return ProblemReport(
                symbol: "arrow.up.circle.fill",
                title: "Push was rejected",
                message: "The remote branch has commits that you don't have yet.",
                hint: "Pull first to combine both, then push again.",
                details: text,
                actions: [ProblemAction(title: "Pull…", style: .prominent) { model.sheet = .pull }])
        }

        if lower.contains("has no upstream branch") || lower.contains("no tracking information") {
            return ProblemReport(
                symbol: "arrow.triangle.branch",
                title: "This branch isn't linked to a remote branch",
                message: "Git doesn't know which remote branch to use.",
                hint: "Push the branch once with “Track” enabled; after that pull and push work directly.",
                details: text,
                actions: [ProblemAction(title: "Push…", style: .prominent) { model.sheet = .push }])
        }

        if lower.contains("permission denied (publickey)") || lower.contains("authentication failed")
            || lower.contains("could not read username") || lower.contains("repository not found")
            || lower.contains("could not read from remote repository") {
            return ProblemReport(
                symbol: "lock.fill",
                title: "Can't connect to the remote",
                message: "Git could not sign in to the remote repository, or you don't have access to it.",
                hint: "Check your SSH key or credentials by running `git fetch` in Terminal for this repository.",
                details: text,
                actions: retry.map { [ProblemAction(title: "Try Again", style: .prominent, run: $0)] } ?? [])
        }

        if lower.contains("index.lock") {
            return ProblemReport(
                symbol: "hourglass",
                title: "Another Git process is busy",
                message: "Git is already working in this repository, for example in Terminal or your editor.",
                hint: "Wait a moment and try again. If nothing is running, remove .git/index.lock.",
                details: text,
                actions: retry.map { [ProblemAction(title: "Try Again", style: .prominent, run: $0)] } ?? [])
        }

        if lower.contains("not fully merged") {
            return ProblemReport(
                symbol: "arrow.triangle.branch",
                title: "This branch isn't fully merged",
                message: "Deleting it would lose commits that exist nowhere else.",
                details: text)
        }

        // Fallback: show git's own sentence, without the "error:/fatal:" noise.
        let lines = text.components(separatedBy: "\n")
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                for prefix in ["error: ", "fatal: ", "hint: ", "warning: "] where l.lowercased().hasPrefix(prefix) {
                    l = String(l.dropFirst(prefix.count))
                }
                return l
            }
            .filter { !$0.isEmpty }
        let first = lines.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Something went wrong."
        return ProblemReport(
            title: action.isEmpty ? "Something went wrong" : "\(action) didn't work",
            message: first,
            files: indented,
            details: text,
            actions: retry.map { [ProblemAction(title: "Try Again", run: $0)] } ?? [])
    }
}

struct ProblemView: View {
    let report: ProblemReport
    @Environment(\.dismiss) private var dismiss
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: report.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 40, height: 40)
                    .background(Theme.orangeSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(report.message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            if !report.files.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(report.files, id: \.self) { file in
                            HStack(spacing: 8) {
                                Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                                Text(file).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            if file != report.files.last { Rectangle().fill(Theme.border).frame(height: 1) }
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(report.files.count) * 29, 170))
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
                .padding(.horizontal, 20)
                .padding(.leading, 54)
            }

            if let hint = report.hint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                    Text(LocalizedStringKey(hint)).font(.system(size: 12)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.leading, 54)
                .padding(.top, 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                        Text("Details")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                if showDetails {
                    ScrollView {
                        Text(report.details)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 140)
                    .background(Theme.subtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.leading, 54)
            .padding(.top, 14)
            .padding(.bottom, 18)

            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 8) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.details, forType: .string)
                }
                .buttonStyle(PillButtonStyle())
                .help("Copy git's full output")
                Spacer()
                let hasPrimary = report.actions.contains { $0.style == .prominent }
                Button(report.actions.isEmpty ? "OK" : "Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: report.actions.isEmpty))
                    .keyboardShortcut(hasPrimary ? .cancelAction : .defaultAction)
                ForEach(report.actions) { action in
                    Button(action.title) {
                        dismiss()
                        action.run()
                    }
                    .buttonStyle(PillButtonStyle(prominent: action.style == .prominent, destructive: action.style == .destructive))
                    .modifier(DefaultActionIf(enabled: action.style == .prominent))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.subtle)
        }
        .frame(width: 500)
        .background(Theme.card)
        .tint(Theme.accent)
    }
}

private struct DefaultActionIf: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.keyboardShortcut(.defaultAction) } else { content }
    }
}
