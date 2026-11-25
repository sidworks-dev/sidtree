import AppKit
import SwiftUI

/// Warm palette with a violet accent. Light and dark values follow the SidTree design files
/// ("SidTree Variant Light" and "SidTree Variant") exactly.
enum Theme {
    static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        dynamic(light, alpha, dark, alpha)
    }

    static func dynamic(_ light: UInt32, _ lightAlpha: CGFloat, _ dark: UInt32, _ darkAlpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        }
    }

    // AppKit
    /// Accent for text, icons and outlines.
    static let nsAccent = dynamic(0x6D28D9, 0xC4B5FD)
    /// Filled accent: buttons, checkboxes, badges with white text.
    static let nsAction = dynamic(0x7C3AED, 0x8B5CF6)
    /// Window chrome behind the repository tabs.
    static let nsChrome = dynamic(0xEBE8E2, 0x292826)
    /// Main content background (history list, diff).
    static let nsCanvas = dynamic(0xF7F6F3, 0x32302D)
    /// Toolbar, sidebar, column headers and the commit box.
    static let nsSidebar = dynamic(0xF3F1EC, 0x2F2D2B)
    /// Side columns: the changes list and the commit details.
    static let nsColumn = dynamic(0xFFFFFF, 0x363431)
    /// Buttons, menus and sheets.
    static let nsCard = dynamic(0xFFFFFF, 0x3A3835)
    static let nsField = dynamic(0xFFFFFF, 0x2C2A28)
    static let nsBorder = dynamic(0xE7E3DC, 0x47433F)
    static let nsControlBorder = dynamic(0xE3DFD8, 0x4A4642)
    static let nsFieldBorder = dynamic(0xDDD8D0, 0x4F4B46)
    static let nsSubtle = dynamic(0xF0EDE7, 0x3E3B38)
    static let nsSelection = dynamic(0x7C3AED, 0.10, 0x8B5CF6, 0.22)
    static let nsText = dynamic(0x1F1D1B, 0xEBE6E0)
    static let nsSecondaryText = dynamic(0x6B655E, 0xB0A9A1)
    static let nsTertiaryText = dynamic(0x857E76, 0x8F8880)
    static let nsMutedText = dynamic(0xA8A199, 0x7D7770)
    static let nsSoftText = dynamic(0x3D3833, 0xD3CEC8)
    static let nsDiffText = dynamic(0x2B2724, 0xDDD7D0)
    static let nsAddedBg = dynamic(0x2F855A, 0.10, 0x50B46E, 0.13)
    static let nsRemovedBg = dynamic(0xC53030, 0.08, 0xDC5A5A, 0.13)
    static let nsAddedText = dynamic(0x2F855A, 0x6FCF8E)
    static let nsRemovedText = dynamic(0xC53030, 0xF08A8A)

    // SwiftUI
    static let accent = Color(nsColor: nsAccent)
    static let action = Color(nsColor: nsAction)
    static let destructiveAction = Color(nsColor: dynamic(0xC53030, 0xB94A48))
    static let chrome = Color(nsColor: nsChrome)
    static let canvas = Color(nsColor: nsCanvas)
    static let sidebar = Color(nsColor: nsSidebar)
    static let column = Color(nsColor: nsColumn)
    static let card = Color(nsColor: nsCard)
    static let field = Color(nsColor: nsField)
    static let border = Color(nsColor: nsBorder)
    static let controlBorder = Color(nsColor: nsControlBorder)
    static let fieldBorder = Color(nsColor: nsFieldBorder)
    static let subtle = Color(nsColor: nsSubtle)
    /// Hover fill of bordered buttons, and the disabled commit button.
    static let controlHover = Color(nsColor: dynamic(0xE7E3DC, 0x47433F))
    /// Hover fill of text buttons inside a column ("Unstage all", "Generate").
    static let pressFill = Color(nsColor: dynamic(0xECE8E1, 0x433F3B))
    /// Background of the selected navigation row.
    static let navSelected = Color(nsColor: dynamic(0xFFFFFF, 0x47433F))
    /// Background of the checked-out branch row.
    static let currentRow = Color(nsColor: dynamic(0xECE8E1, 0x433F3B))
    static let selection = Color(nsColor: nsSelection)
    static let text = Color(nsColor: nsText)
    static let secondaryText = Color(nsColor: nsSecondaryText)
    static let tertiaryText = Color(nsColor: nsTertiaryText)
    static let mutedText = Color(nsColor: nsMutedText)
    static let softText = Color(nsColor: nsSoftText)
    static let diffText = Color(nsColor: nsDiffText)
    static let addedBg = Color(nsColor: nsAddedBg)
    static let removedBg = Color(nsColor: nsRemovedBg)
    static let addedText = Color(nsColor: nsAddedText)
    static let removedText = Color(nsColor: nsRemovedText)
    static let hunkBackground = Color(nsColor: dynamic(0xFFFFFF, 0x383633))
    static let hunkHeader = Color(nsColor: dynamic(0xFAF9F6, 0x3D3A37))
    static let checkboxBorder = Color(nsColor: dynamic(0xB9B3AA, 0x6A645E))
    static let badgeBorder = Color(nsColor: dynamic(0xD6D1C9, 0x5A554F))
    static let accentHover = Color(nsColor: dynamic(0x7C3AED, 0.08, 0x8B5CF6, 0.16))
    static let destructiveHover = Color(nsColor: dynamic(0xC53030, 0.08, 0xF08A8A, 0.12))
    static let avatarFill = Color(nsColor: dynamic(0xEDE9FE, 0x4A3A7A))
    static let avatarText = Color(nsColor: dynamic(0x5B21B6, 0xDDD6FE))
    /// Initial tile of an inactive tab or repository row.
    static let tileFill = Color(nsColor: dynamic(0xEDE9FE, 0x3B3350))

    static let green = Color(nsColor: nsAddedText)
    static let greenSoft = Color(nsColor: dynamic(0x2F855A, 0.10, 0x6FCF8E, 0.14))
    static let orange = Color(nsColor: dynamic(0xA16207, 0xE6B35A))
    static let orangeSoft = Color(nsColor: dynamic(0xA16207, 0.10, 0xE6B35A, 0.16))
    /// Filled warning badge (pull count).
    static let amber = Color(nsColor: dynamic(0xA16207, 0xE6B35A))
    /// Text on a filled amber badge.
    static let onAmber = Color(nsColor: nsChrome)
    static let red = Color(nsColor: nsRemovedText)
    static let redSoft = Color(nsColor: dynamic(0xC53030, 0.08, 0xF08A8A, 0.14))
    static let blue = Color(nsColor: dynamic(0x2563EB, 0x8AB4F8))
    static let blueSoft = Color(nsColor: dynamic(0x2563EB, 0.08, 0x8AB4F8, 0.14))
    static let violetSoft = Color(nsColor: dynamic(0xEDE9FE, 0x3B3350))
    static let graySoft = Color(nsColor: dynamic(0xECE8E1, 0x433F3B))

    static let radius: CGFloat = 10
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
