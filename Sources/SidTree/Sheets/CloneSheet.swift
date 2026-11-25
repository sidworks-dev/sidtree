import AppKit
import SwiftUI

struct CloneSheet: View {
    let defaultParent: URL?
    let onCloned: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var remote = ""
    @State private var parent: URL?
    @State private var name = ""
    @State private var nameEdited = false
    @State private var running = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36).background(Theme.violetSoft, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clone Repository").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Uses your SSH keys / keychain credentials").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(20)
            Rectangle().fill(Theme.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Source URL")
                    StyledTextField(placeholder: "git@bitbucket.org:team/project.git", text: $remote)
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Destination folder")
                    HStack {
                        Text(parent.map(DisplayPath.of) ?? "Choose…")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { chooseParent() }.buttonStyle(PillButtonStyle(compact: true))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Name")
                    StyledTextField(placeholder: "project", text: Binding(get: { name }, set: { name = $0; nameEdited = true }))
                }
                if let error {
                    Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.red).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                if running {
                    ProgressView().controlSize(.small)
                    Text("Cloning…").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction).disabled(running)
                Button("Clone") { clone() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(running || remote.isEmpty || parent == nil || name.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Theme.subtle)
        }
        .frame(width: 520)
        .background(Theme.card)
        .tint(Theme.accent)
        .onAppear { parent = defaultParent ?? FileManager.default.homeDirectoryForCurrentUser }
        .onChange(of: remote) { _, value in
            guard !nameEdited else { return }
            var n = value.trimmingCharacters(in: .whitespaces)
            if n.hasSuffix("/") { n.removeLast() }
            n = String(n.split(whereSeparator: { $0 == "/" || $0 == ":" }).last ?? "")
            if n.hasSuffix(".git") { n.removeLast(4) }
            name = n
        }
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK { parent = panel.url }
    }

    private func clone() {
        guard let parent else { return }
        running = true
        error = nil
        let dest = parent.appendingPathComponent(name)
        let src = remote.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await GitRunner.check(["clone", "--", src, dest.path], in: parent)
                running = false
                dismiss()
                onCloned(dest)
            } catch {
                running = false
                self.error = error.localizedDescription
            }
        }
    }
}
