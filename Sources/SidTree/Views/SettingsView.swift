import SwiftUI

struct SettingsView: View {
    @AppStorage("settings.tab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag("ai")
        }
        .frame(width: 580)
        .tint(Theme.accent)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("autoFetchMinutes") private var autoFetchMinutes = 10
    @AppStorage("historyLimit") private var historyLimit = 10000
    @AppStorage("terminalApp") private var terminalApp = "Terminal"
    @AppStorage("optimizeRepositories") private var optimizeRepositories = true
    @AppStorage(UpdateChecker.autoCheckKey) private var autoUpdate = true
    @ObservedObject private var appearance = AppearanceController.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance.mode) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Remote") {
                Picker("Fetch automatically", selection: $autoFetchMinutes) {
                    Text("Never").tag(0)
                    Text("Every 5 minutes").tag(5)
                    Text("Every 10 minutes").tag(10)
                    Text("Every 30 minutes").tag(30)
                }
            }
            Section("History") {
                Picker("Commits loaded initially", selection: $historyLimit) {
                    Text("1.000").tag(1000)
                    Text("2.500").tag(2500)
                    Text("10.000").tag(10000)
                    Text("50.000").tag(50000)
                }
                Text("More commits load automatically while scrolling.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Performance") {
                Toggle("Optimize repositories automatically", isOn: $optimizeRepositories)
                Text("Writes git's commit-graph when missing (same as `git maintenance`). Makes history load up to 10× faster on large repositories.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tools") {
                Picker("Terminal", selection: $terminalApp) {
                    Text("Terminal").tag("Terminal")
                    Text("iTerm").tag("iTerm")
                    Text("Warp").tag("Warp")
                    Text("Ghostty").tag("Ghostty")
                }
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                Text("Releases come from github.com/\(UpdateChecker.repo). The repository is private, so the GitHub CLI login (`gh auth login`) is used when needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("SidTree \(AppInfo.version) · Git: \(GitRunner.gitPath)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
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
                Text("Uses the CLI already installed and logged in on this Mac. Only the staged diff (compacted) and recent commit subjects are sent to the provider. Off by default.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("AI commit messages")
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
                    Text("Runs without tools, MCP servers, hooks or plugins and with your instruction as the only system prompt (~800 tokens overhead with Haiku, ~2 s).")
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
                    Text("Runs with your instruction instead of Codex's agent prompt and ignores your Codex config (MCP servers, profiles): a few hundred tokens instead of ~17k.")
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
                        Text("Used as the system prompt. Keep it short: every word is sent with each request. Text you type in the commit box before generating is passed along as your intent.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Prompt")
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
        .task {
            for p in [AIProvider.claude, .codex] {
                if let path = await AICommitGenerator.locate(p) { found[p] = path }
            }
            checked = true
        }
    }
}
