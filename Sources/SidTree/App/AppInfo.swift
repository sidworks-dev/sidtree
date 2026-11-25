import AppKit

enum AppInfo {
    static let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    static let logo: NSImage? = Bundle.main.image(forResource: "sidworks-logo")
}
