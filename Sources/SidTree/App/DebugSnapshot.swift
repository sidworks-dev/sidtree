import AppKit

/// Development aid: `SIDTREE_SNAPSHOT=/path/out.png` renders the main window to a PNG after launch.
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["SIDTREE_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["SIDTREE_SNAPSHOT_DELAY"] ?? "") ?? 3
        if ProcessInfo.processInfo.environment["SIDTREE_DEBUG_CLOSE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(delay - 1.5, 0.5)) {
                NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("repo-") == true && $0.isVisible }?.performClose(nil)
            }
        }
        if let pane = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_SETTINGS"] {
            UserDefaults.standard.set(pane, forKey: "settings.tab")
            DispatchQueue.main.asyncAfter(deadline: .now() + max(delay - 1.5, 0.5)) {
                NotificationCenter.default.post(name: .openSettingsRequest, object: "debug")
            }
            if let next = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_SETTINGS_SWITCH"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + max(delay - 0.7, 0.8)) {
                    UserDefaults.standard.set(next, forKey: "settings.tab")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let appearance = ProcessInfo.processInfo.environment["SIDTREE_APPEARANCE"] {
                NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if ProcessInfo.processInfo.environment["SIDTREE_DEBUG_WINDOWS"] != nil {
                    for w in NSApp.windows {
                        let line = "window id=\(w.identifier?.rawValue ?? "-") title=\(w.title) visible=\(w.isVisible)\n"
                        FileHandle.standardError.write(Data(line.utf8))
                    }
                }
                let settings = ProcessInfo.processInfo.environment["SIDTREE_DEBUG_SETTINGS"] != nil
                guard let main = settings ? NSApp.windows.first(where: { $0.isVisible && $0.title.contains("Settings") })
                        : NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }),
                      case let window = main.attachedSheet ?? main,
                      let view = window.contentView?.superview ?? window.contentView,
                      // Always 2×, whatever screen the window opened on, so screenshots stay sharp.
                      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                                 pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
                rep.size = view.bounds.size
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
