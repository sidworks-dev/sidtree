import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, repositories, tools, ai, updates
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .repositories: return "Repositories"
        case .tools: return "Editor & Tools"
        case .ai: return "AI Commit Messages"
        case .updates: return "Updates"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Appearance and where your projects live"
        case .repositories: return "Fetching, history and repository upkeep"
        case .tools: return "Apps SidTree opens your code in"
        case .ai: return "Write commit messages with Claude Code or Codex"
        case .updates: return "Keep SidTree up to date"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .repositories: return "externaldrive.fill"
        case .tools: return "hammer.fill"
        case .ai: return "sparkles"
        case .updates: return "arrow.down.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(nsColor: .systemGray)
        case .repositories: return Color(nsColor: .systemBlue)
        case .tools: return Color(nsColor: .systemOrange)
        case .ai: return Theme.action
        case .updates: return Color(nsColor: .systemGreen)
        }
    }
}

struct SettingsView: View {
    /// Remembered between openings, and set by other parts of the app ("Choose an editor in Settings").
    @AppStorage("settings.tab") private var storedTab = SettingsPane.general.rawValue
    /// The one source of truth for both the sidebar highlight and the content.
    @State private var pane = SettingsPane.general

    private static func pane(for tab: String) -> SettingsPane { SettingsPane(rawValue: tab) ?? .general }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.title).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(pane.subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 4)
                Group {
                    switch pane {
                    case .general: GeneralSettingsView()
                    case .repositories: RepositorySettingsView()
                    case .tools: ToolSettingsView()
                    case .ai: AISettingsView()
                    case .updates: UpdateSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Theme.canvas)
        }
        .frame(width: 800, height: 600)
        .tint(Theme.accent)
        .onAppear { pane = Self.pane(for: storedTab) }
        .onChange(of: storedTab) { _, tab in pane = Self.pane(for: tab) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Same left edge and icon column as the rows below: 7pt row inset, text after a 9pt gap.
            HStack(spacing: 9) {
                LogoMark(size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("SidTree").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Version \(AppInfo.version)").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 7) }
            .padding(.bottom, 8)
            ForEach(SettingsPane.allCases) { item in
                SettingsNavRow(pane: item, selected: item == pane) {
                    pane = item
                    storedTab = item.rawValue
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }
}

private struct SettingsNavRow: View {
    let pane: SettingsPane
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(pane.tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(pane.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Theme.navSelected : (hover ? Theme.subtle : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
    }
}

/// Helper text under a setting.
private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryText).fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var appearance = AppearanceController.shared
    @AppStorage(ProjectFolder.key) private var projectFolder = ""

    var body: some View {
        Form {
            Section("Appearance") {
                HStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases) { mode in
                        ThemeTile(mode: mode, selected: appearance.mode == mode) { appearance.mode = mode }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Default project folder") {
                    HStack(spacing: 8) {
                        if !projectFolder.isEmpty {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: projectFolder)).resizable().frame(width: 16, height: 16)
                        }
                        Text(projectFolder.isEmpty ? "Not set" : DisplayPath.of(projectFolder))
                            .foregroundStyle(projectFolder.isEmpty ? Theme.tertiaryText : Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                        if !projectFolder.isEmpty {
                            Button { projectFolder = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .handCursor()
                                .foregroundStyle(Theme.tertiaryText)
                                .help("Clear")
                        }
                    }
                }
                Hint("Open Repository starts here, and new clones are placed in this folder.")
            } header: {
                Text("Projects")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your projects"
        if let current = ProjectFolder.url { panel.directoryURL = current }
        if panel.runModal() == .OK, let url = panel.url { projectFolder = url.path }
    }
}

/// Theme choice as a small window preview.
private struct ThemeTile: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview
                    .frame(width: 112, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Theme.action : Theme.border, lineWidth: selected ? 2.5 : 1))
                Text(mode.title).font(.system(size: 12, weight: selected ? .semibold : .regular)).foregroundStyle(Theme.text)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniWindow(dark: false).frame(width: 56, alignment: .leading).clipped()
                MiniWindow(dark: true).frame(width: 112).frame(width: 56, alignment: .trailing).clipped()
            }
        }
    }
}

private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let chrome = Color(nsColor: NSColor(hex: dark ? 0x292826 : 0xEBE8E2))
        let side = Color(nsColor: NSColor(hex: dark ? 0x2F2D2B : 0xF3F1EC))
        let canvas = Color(nsColor: NSColor(hex: dark ? 0x32302D : 0xF7F6F3))
        let line = Color(nsColor: NSColor(hex: dark ? 0x47433F : 0xE7E3DC))
        VStack(spacing: 0) {
            chrome.frame(height: 10)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: NSColor(hex: 0x8B5CF6))).frame(width: 18, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 14, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 16, height: 4)
                    Spacer()
                }
                .padding(5)
                .frame(width: 30)
                .frame(maxHeight: .infinity)
                .background(side)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(line).frame(width: CGFloat(52 - i * 8), height: 4)
                    }
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(canvas)
            }
        }
    }
}

struct RepositorySettingsView: View {
    @AppStorage("autoFetchMinutes") private var autoFetchMinutes = 10
    @AppStorage("historyLimit") private var historyLimit = 10000
    @AppStorage("optimizeRepositories") private var optimizeRepositories = true

    var body: some View {
        Form {
            Section("Remote") {
                Picker("Fetch automatically", selection: $autoFetchMinutes) {
                    Text("Never").tag(0)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 10 minutes").tag(10)
                    Text("Every 30 minutes").tag(30)
                }
                Hint("Keeps the Pull and Push counts current for every open tab.")
            }
            Section("History") {
                Picker("Commits loaded initially", selection: $historyLimit) {
                    Text("1,000").tag(1000)
                    Text("2,500").tag(2500)
                    Text("10,000").tag(10000)
                    Text("50,000").tag(50000)
                }
                Hint("More commits load automatically while scrolling.")
            }
            Section("Performance") {
                Toggle("Optimize repositories automatically", isOn: $optimizeRepositories)
                Hint("Writes git's commit-graph when missing (same as `git maintenance`). Makes history load up to 10× faster on large repositories.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct ToolSettingsView: View {
    @AppStorage(EditorSettings.key) private var editorPath = ""
    @AppStorage("terminalApp") private var terminalApp = "Terminal"
    @State private var editors: [EditorSettings.Editor] = []

    var body: some View {
        Form {
            Section {
                Picker("Open code in", selection: $editorPath) {
                    Text("None").tag("")
                    if !editors.isEmpty { Divider() }
                    ForEach(editors) { editor in
                        Label { Text(editor.name) } icon: { Image(nsImage: resized(editor.icon)) }
                            .tag(editor.url.path)
                    }
                    if !editorPath.isEmpty, !editors.contains(where: { $0.url.path == editorPath }) {
                        Text(FileManager.default.displayName(atPath: editorPath)).tag(editorPath)
                    }
                }
                HStack {
                    Hint("Used by Open in Editor (⇧⌘E), the toolbar button and file menus. "
                         + "Files that could run code (apps, scripts, executables) also open here instead of running.")
                    Spacer()
                    Button("Choose Other App…") {
                        if let editor = EditorSettings.chooseOther() { editorPath = editor.url.path }
                    }
                }
            } header: {
                Text("Editor")
            }
            Section("Terminal") {
                Picker("Open in Terminal uses", selection: $terminalApp) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm").tag("iTerm")
                    Text("Warp").tag("Warp")
                    Text("Ghostty").tag("Ghostty")
                }
            }
            Section("Command line") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("sidtree command")
                        Hint("Run `sidtree .` in a repository to open it in SidTree.")
                    }
                    Spacer()
                    Button("Install…") { CommandLineTools.install() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { editors = EditorSettings.installed() }
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

struct UpdateSettingsView: View {
    @AppStorage(UpdateChecker.autoCheckKey) private var autoUpdate = true
    @AppStorage(UpdateChecker.startupKey) private var checkOnStartup = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Automatic checks") {
                Toggle("Check for updates on startup", isOn: $checkOnStartup)
                Toggle("Check periodically while running (every 6 hours)", isOn: $autoUpdate)
            }
            Section {
                LabeledContent("Installed") { Text("SidTree \(AppInfo.version)") }
                LabeledContent("Git") { Text(GitRunner.gitPath).font(.system(size: 12, design: .monospaced)) }
                HStack {
                    Hint("Updates come from the releases on github.com/\(UpdateChecker.repo) and are checked for SidTree's signature before installing.")
                    Spacer()
                    Button("Check Now") {
                        openWindow(id: "update")
                        Task { await UpdateChecker.shared.check(userInitiated: true) }
                    }
                }
            } header: {
                Text("Version")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct AISettingsView: View {
    @AppStorage(AISettings.provider) private var provider = AIProvider.off.rawValue
    @AppStorage(AISettings.claudeModel) private var claudeModel = ClaudeModel.haiku.rawValue
    @AppStorage(AISettings.claudeCustom) private var claudeCustom = ""
    @AppStorage(AISettings.codexModel) private var codexModel = ""
    @AppStorage(AISettings.codexCustom) private var codexCustom = ""
    @AppStorage(AISettings.codexEffort) private var codexEffort = "low"
    @AppStorage(AISettings.instruction) private var instruction = AISettings.defaultInstruction
    @AppStorage(AISettings.maxDiff) private var maxDiff = 12_000
    @AppStorage(AISettings.singleLine) private var singleLine = true
    @AppStorage(AISettings.prepare) private var prepare = true
    @State private var found: [AIProvider: String] = [:]
    @State private var checked = false
    private let codexModels = AISettings.codexModels()

    private var selected: AIProvider { AIProvider(rawValue: provider) ?? .off }

    var body: some View {
        Form {
            Section {
                Picker("Generate commit messages with", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                ForEach([AIProvider.claude, .codex]) { p in
                    HStack(spacing: 6) {
                        Image(systemName: found[p] != nil ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(found[p] != nil ? Theme.green : Color.secondary)
                        Text(p.title).font(.callout)
                        Spacer()
                        Text(found[p] ?? (checked ? "not installed" : "checking…"))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Text("Uses the CLI already installed and logged in on this Mac. Only the staged diff (compacted) "
                     + "and recent commit subjects are sent to the provider. Off by default.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Provider")
            }

            if selected == .claude {
                Section("Claude Code") {
                    Picker("Model", selection: $claudeModel) {
                        ForEach(ClaudeModel.allCases) { Text($0.title).tag($0.rawValue) }
                        Text("Custom model ID…").tag(AISettings.customModelTag)
                    }
                    if claudeModel == AISettings.customModelTag {
                        TextField("Model ID", text: $claudeCustom, prompt: Text("e.g. claude-haiku-5-5"))
                    }
                    Text("Runs without tools, MCP servers, hooks or plugins and with your instruction as the only "
                         + "system prompt (~800 tokens overhead with Haiku, ~2 s).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if selected == .codex {
                Section("Codex") {
                    Picker("Model", selection: $codexModel) {
                        Text("Automatic — fastest available (\(AISettings.autoCodexModel ?? "CLI default"))").tag("")
                        ForEach(codexModels, id: \.slug) { Text($0.name).tag($0.slug) }
                        Text("Custom model ID…").tag(AISettings.customModelTag)
                    }
                    if codexModel == AISettings.customModelTag {
                        TextField("Model ID", text: $codexCustom, prompt: Text("model slug"))
                    }
                    Picker("Reasoning effort", selection: $codexEffort) {
                        Text("Low — fastest (recommended)").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    Text("Runs with your instruction instead of Codex's agent prompt and ignores your Codex config "
                         + "(MCP servers, profiles): a few hundred tokens instead of ~17k.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if selected != .off {
                Section {
                    Toggle("Summary line only (recommended)", isOn: $singleLine)
                    Toggle("Prepare message in the background", isOn: $prepare)
                    Text("Starts generating as soon as you stage files, so Generate fills the message instantly. Uses one request per staging change.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Diff sent to the model", selection: $maxDiff) {
                        Text("Small — max ~1.5k tokens").tag(6_000)
                        Text("Medium — max ~3k tokens (recommended)").tag(12_000)
                        Text("Large — max ~8k tokens").tag(30_000)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Instruction")
                            Spacer()
                            Button("Reset to Default") { instruction = AISettings.defaultInstruction }
                                .disabled(instruction == AISettings.defaultInstruction)
                        }
                        TextEditor(text: $instruction)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 150)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                        Text("Used as the system prompt. Keep it short: every word is sent with each request. "
                             + "Text you type in the commit box before generating is passed along as your intent.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Prompt")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            for p in [AIProvider.claude, .codex] {
                if let path = await AICommitGenerator.locate(p) { found[p] = path }
            }
            checked = true
        }
    }
}
