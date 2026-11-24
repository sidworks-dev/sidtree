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

/// Turns git's output into a readable `ProblemReport`. Each recognizer handles one kind of failure.
@MainActor
enum ProblemInterpreter {
    /// Everything a recognizer needs to know about a failed operation.
    struct Failure {
        let text: String
        let lower: String
        /// Indented lines in git's output, which are usually file paths.
        let indentedLines: [String]
        let action: String
        let model: RepoModel
        let retry: (() -> Void)?
        let stashAndRetry: (() -> Void)?

        func contains(_ needles: String...) -> Bool { needles.contains { lower.contains($0) } }

        var tryAgain: [ProblemAction] {
            retry.map { [ProblemAction(title: "Try Again", style: .prominent, run: $0)] } ?? []
        }
    }

    /// - Parameters:
    ///   - retry: re-runs the failed operation.
    ///   - stashAndRetry: stashes local changes (incl. untracked) and re-runs the operation.
    static func report(for raw: String, label: String, model: RepoModel,
                       retry: (() -> Void)?, stashAndRetry: (() -> Void)?) -> ProblemReport {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let failure = Failure(
            text: text,
            lower: text.lowercased(),
            indentedLines: text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("\t") || $0.hasPrefix("    ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            action: label.replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces),
            model: model, retry: retry, stashAndRetry: stashAndRetry)

        let recognizers: [(Failure) -> ProblemReport?] = [
            localChangesInTheWay, conflicts, pushRejected, noUpstream, cannotConnect, gitBusy, branchNotMerged
        ]
        for recognize in recognizers {
            if let report = recognize(failure) { return report }
        }
        return fallback(failure)
    }

    /// Local changes would be overwritten (checkout, merge, pull, cherry-pick, stash apply…).
    private static func localChangesInTheWay(_ f: Failure) -> ProblemReport? {
        guard f.contains("would be overwritten by") else { return nil }
        let untracked = f.contains("untracked working tree files")
        let what: String
        if f.contains("by checkout") {
            what = "Switching branches"
        } else if f.contains("by merge") {
            what = "This merge"
        } else {
            what = "This action"
        }
        var report = ProblemReport(
            symbol: "tray.full.fill",
            title: untracked ? "Untracked files are in the way" : "Your local changes are in the way",
            message: "\(what) would overwrite \(untracked ? "untracked files" : "uncommitted changes") in:",
            files: f.indentedLines,
            hint: "Stash them to keep them safe. You can restore them later from Stashes in the sidebar.",
            details: f.text)
        if let stashAndRetry = f.stashAndRetry {
            report.actions.append(ProblemAction(title: f.contains("by checkout") ? "Stash & Switch" : "Stash & Continue",
                                                style: .prominent, run: stashAndRetry))
        }
        return report
    }

    /// Merge, rebase or cherry-pick stopped on conflicts.
    private static func conflicts(_ f: Failure) -> ProblemReport? {
        guard f.contains("conflict"),
              f.contains("merge conflict", "automatic merge failed", "could not apply", "after resolving") else { return nil }
        let files = f.text.components(separatedBy: "\n").compactMap { line -> String? in
            guard let range = line.range(of: "Merge conflict in ") else { return nil }
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        let model = f.model
        return ProblemReport(
            symbol: "arrow.triangle.merge",
            title: "Conflicts need your attention",
            message: files.isEmpty ? "Some files were changed on both sides." : "These files were changed on both sides:",
            files: files,
            hint: "Resolve them in File Status, stage them and commit (or continue the rebase). You can also abort and go back.",
            details: f.text,
            actions: [
                ProblemAction(title: "Abort", style: .destructive) { model.abortOperation() },
                ProblemAction(title: "Resolve Conflicts", style: .prominent) { model.sidebarSelection = .fileStatus }
            ])
    }

    /// Push rejected because the remote moved on.
    private static func pushRejected(_ f: Failure) -> ProblemReport? {
        guard f.contains("[rejected]", "non-fast-forward", "fetch first", "updates were rejected") else { return nil }
        let model = f.model
        return ProblemReport(
            symbol: "arrow.up.circle.fill",
            title: "Push was rejected",
            message: "The remote branch has commits that you don't have yet.",
            hint: "Pull first to combine both, then push again.",
            details: f.text,
            actions: [ProblemAction(title: "Pull…", style: .prominent) { model.sheet = .pull }])
    }

    private static func noUpstream(_ f: Failure) -> ProblemReport? {
        guard f.contains("has no upstream branch", "no tracking information") else { return nil }
        let model = f.model
        return ProblemReport(
            symbol: "arrow.triangle.branch",
            title: "This branch isn't linked to a remote branch",
            message: "Git doesn't know which remote branch to use.",
            hint: "Push the branch once with “Track” enabled; after that pull and push work directly.",
            details: f.text,
            actions: [ProblemAction(title: "Push…", style: .prominent) { model.sheet = .push }])
    }

    private static func cannotConnect(_ f: Failure) -> ProblemReport? {
        guard f.contains("permission denied (publickey)", "authentication failed", "could not read username",
                         "repository not found", "could not read from remote repository") else { return nil }
        return ProblemReport(
            symbol: "lock.fill",
            title: "Can't connect to the remote",
            message: "Git could not sign in to the remote repository, or you don't have access to it.",
            hint: "Check your SSH key or credentials by running `git fetch` in Terminal for this repository.",
            details: f.text,
            actions: f.tryAgain)
    }

    private static func gitBusy(_ f: Failure) -> ProblemReport? {
        guard f.contains("index.lock") else { return nil }
        return ProblemReport(
            symbol: "hourglass",
            title: "Another Git process is busy",
            message: "Git is already working in this repository, for example in Terminal or your editor.",
            hint: "Wait a moment and try again. If nothing is running, remove .git/index.lock.",
            details: f.text,
            actions: f.tryAgain)
    }

    private static func branchNotMerged(_ f: Failure) -> ProblemReport? {
        guard f.contains("not fully merged") else { return nil }
        return ProblemReport(
            symbol: "arrow.triangle.branch",
            title: "This branch isn't fully merged",
            message: "Deleting it would lose commits that exist nowhere else.",
            details: f.text)
    }

    /// Shows git's own sentence, without the "error:/fatal:" noise.
    private static func fallback(_ f: Failure) -> ProblemReport {
        let lines = f.text.components(separatedBy: "\n")
            .map { line -> String in
                var cleaned = line.trimmingCharacters(in: .whitespaces)
                for prefix in ["error: ", "fatal: ", "hint: ", "warning: "] where cleaned.lowercased().hasPrefix(prefix) {
                    cleaned = String(cleaned.dropFirst(prefix.count))
                }
                return cleaned
            }
            .filter { !$0.isEmpty }
        let first = lines.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Something went wrong."
        return ProblemReport(
            title: f.action.isEmpty ? "Something went wrong" : "\(f.action) didn't work",
            message: first,
            files: f.indentedLines,
            details: f.text,
            actions: f.retry.map { [ProblemAction(title: "Try Again", run: $0)] } ?? [])
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
