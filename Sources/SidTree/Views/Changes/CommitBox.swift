import AppKit
import SwiftUI

struct CommitBox: View {
    @Bindable var model: RepoModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AIGenerateControl(model: model)
                Button { model.amend.toggle() } label: {
                    HStack(spacing: 6) {
                        CheckBox(checked: model.amend, size: 14)
                        Text("Amend").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .handCursor()
                .help("Amend the last commit")
                Spacer(minLength: 4)
                let summary = model.commitMessage.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
                if summary.count > 50 {
                    Text("\(summary.count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(summary.count > 72 ? Theme.orange : Theme.tertiaryText)
                        .help("Summary length (keep under 72)")
                }
            }

            ZStack(alignment: .topLeading) {
                if model.commitMessage.isEmpty {
                    Text(model.status.staged.isEmpty && !model.amend
                         ? "Stage files, then write a commit message…" : "Commit message (first line is the summary)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 10)
                        .padding(.top, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.commitMessage)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .focused($focused)
            }
            .frame(minHeight: 60, maxHeight: .infinity)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focused ? Theme.action : Theme.fieldBorder, lineWidth: 1))

            CommitActionControl(model: model)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
        .onChange(of: model.commitFocusToken) { _, _ in focused = true }
        .onAppear { if model.commitFocusToken > 0 { focused = true } }
    }
}

/// The main button performs the remembered action; the arrow changes it without committing.
struct CommitActionControl: View {
    @Bindable var model: RepoModel
    @State private var hoverMain = false
    @State private var hoverMenu = false

    private var disabled: Bool { model.committing || !model.canCommit || (model.pushAfterCommit && model.currentBranch == nil) }
    private var title: String {
        let verb = model.amend ? "Amend" : "Commit"
        let action = model.pushAfterCommit ? "\(verb) & Push" : verb
        let count = model.status.staged.count
        guard count > 0, !model.pushAfterCommit else { return action }
        return "\(action) \(count) \(count == 1 ? "file" : "files")"
    }
    private var help: String {
        guard model.pushAfterCommit else { return "Commit staged changes (⌘Return)" }
        guard let branch = model.currentBranch else { return "Choose Commit or check out a branch before pushing" }
        let target = model.currentBranchInfo?.upstream ?? "\(model.remotes.first ?? "origin")/\(branch)"
        return "Commit and push to \(target) (⌘Return)"
    }
    private var foreground: Color { disabled && !model.committing ? Theme.tertiaryText : .white }

    var body: some View {
        HStack(spacing: 0) {
            Button { model.commit() } label: {
                Group {
                    if model.committing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).tint(.white).frame(width: 12, height: 12)
                            Text("Processing…")
                        }
                    } else {
                        Text(title)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 30)
                .background(hoverMain && !disabled ? .white.opacity(0.1) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .onHover { hoverMain = $0 }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(disabled)
            .help(model.committing ? "Committing…" : help)

            Rectangle().fill(foreground.opacity(0.3)).frame(width: 1, height: 16)
            Menu {
                Button("Commit") { model.pushAfterCommit = false }
                Button("Commit & Push") { model.pushAfterCommit = true }
                    .disabled(model.currentBranch == nil)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(width: 24, height: 30)
                    .background(hoverMenu ? .white.opacity(0.1) : .clear)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .handCursor()
            .menuIndicator(.hidden)
            .tint(foreground)
            .fixedSize()
            .onHover { hoverMenu = $0 }
            .help("Choose Commit or Commit & Push; remembered for this repository")
            .accessibilityLabel("Commit action")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foreground)
        .background(disabled && !model.committing ? Theme.controlHover : Theme.action,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .opacity(model.committing ? 0.8 : 1)
    }
}

/// "✨ Generate ▾" split button: generate, or switch provider/model and open the AI settings.
struct AIGenerateControl: View {
    let model: RepoModel
    @AppStorage(AISettings.provider) private var provider = AIProvider.off.rawValue
    @AppStorage(AISettings.claudeModel) private var claudeModel = ClaudeModel.haiku.rawValue
    @AppStorage(AISettings.codexModel) private var codexModel = ""
    @AppStorage("settings.tab") private var settingsTab = "general"
    @Environment(\.openSettings) private var openSettings
    @State private var hoverMain = false
    @State private var hoverMenu = false

    private var current: AIProvider { AIProvider(rawValue: provider) ?? .off }
    private var canGenerate: Bool { current != .off && (!model.status.staged.isEmpty || model.amend) }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if current == .off { showMenu() } else { model.generateCommitMessage() }
            } label: {
                HStack(spacing: 5) {
                    if model.aiGenerating {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                        Text("Generating…")
                    } else {
                        Image(systemName: "sparkle").font(.system(size: 10.5, weight: .semibold))
                        Text("Generate")
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(height: 30)
                .background(hoverMain ? Theme.pressFill : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .onHover { hoverMain = $0 }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(model.aiGenerating || (current != .off && !canGenerate))
            .opacity(model.aiGenerating ? 0.6 : (current != .off && !canGenerate ? 0.45 : 1))
            .help(current == .off ? "Set up AI commit messages" :
                    "Write a commit message with \(current.title) · \(modelLabel) (⌥⌘G). Text already in the box is used as your intent.")

            Rectangle().fill(Theme.fieldBorder).frame(width: 1, height: 16)

            Button(action: showMenu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 20, height: 30)
                    .background(hoverMenu ? Theme.pressFill : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .onHover { hoverMenu = $0 }
            .help("Switch AI model or open AI settings")
        }
        .fixedSize()
        .font(.system(size: 13))
        .foregroundStyle(Theme.softText)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.fieldBorder, lineWidth: 1))
    }

    private var modelLabel: String {
        switch current {
        case .claude: return AISettings.currentClaudeModel.capitalized
        case .codex: return AISettings.currentCodexModel ?? "default"
        case .off: return ""
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        if model.aiGenerating {
            menu.addItem(ClosureMenuItem("Cancel Generating") { model.cancelCommitMessageGeneration() })
            menu.addItem(.separator())
        }
        menu.addItem(.sectionHeader(title: "Generate with"))
        for p in AIProvider.allCases {
            let item = ClosureMenuItem(p == .off ? "Off" : p.title) { provider = p.rawValue }
            item.state = current == p ? .on : .off
            menu.addItem(item)
        }
        switch current {
        case .claude:
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Claude model"))
            for m in ClaudeModel.allCases {
                let item = ClosureMenuItem(m.title) { claudeModel = m.rawValue }
                item.state = claudeModel == m.rawValue ? .on : .off
                menu.addItem(item)
            }
            if claudeModel == AISettings.customModelTag {
                let item = ClosureMenuItem("Custom: \(AISettings.currentClaudeModel)") {}
                item.state = .on
                menu.addItem(item)
            }
        case .codex:
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Codex model"))
            let auto = ClosureMenuItem("Automatic — fastest (\(AISettings.autoCodexModel ?? "CLI default"))") { codexModel = "" }
            auto.state = codexModel.isEmpty ? .on : .off
            menu.addItem(auto)
            for m in AISettings.codexModels() {
                let item = ClosureMenuItem(m.name) { codexModel = m.slug }
                item.state = codexModel == m.slug ? .on : .off
                menu.addItem(item)
            }
        case .off:
            break
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("AI Settings…") {
            settingsTab = "ai"
            openSettings()
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
