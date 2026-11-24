import AppKit

enum CommandLineTools {
    @MainActor
    static func install() {
        guard let launcher = Bundle.main.url(forResource: "sidtree", withExtension: nil) else {
            let alert = NSAlert()
            alert.messageText = "Command Line Tools Unavailable"
            alert.informativeText = "The sidtree launcher is missing from this app. Reinstall SidTree and try again."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = launcher
        process.arguments = ["--install"]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let alert = NSAlert()
            alert.messageText = process.terminationStatus == 0 ? "Command Line Tools Installed" : "Could Not Install Command Line Tools"
            alert.informativeText = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            alert.alertStyle = process.terminationStatus == 0 ? .informational : .warning
            alert.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
