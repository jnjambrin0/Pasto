import AppKit
import PastoCore

/// The colours cards are drawn with. Dynamic ones follow the appearance of the view that uses
/// them, which for a card's content is the appearance derived from its background.
enum CardColor {
    static let primaryText = NSColor.dynamic(
        light: NSColor.black.withAlphaComponent(0.85),
        dark: NSColor.white.withAlphaComponent(0.85)
    )
    /// With "Increase contrast" on, the system's secondary label colour, which that setting
    /// strengthens; cards configure their text again when the appearance changes.
    static let secondaryText = NSColor(name: nil) { appearance in
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            return .secondaryLabelColor
        }
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.5)
    }
    /// The filled squares of the checkerboard behind images.
    static let checkerSquare = NSColor.dynamic(
        light: NSColor.black.withAlphaComponent(0.05),
        dark: NSColor.white.withAlphaComponent(0.05)
    )

    /// Every card except text and colour.
    static let standardBackground = NSColor.textBackgroundColor
    static let plainTextBackground = NSColor.dynamic(light: .white, dark: NSColor(rgb: 0x141414))
    /// Rich text with a translucent background of its own, and the top of the link gradient.
    static let fallbackBackground = NSColor.dynamic(light: .white, dark: .windowBackgroundColor)
    static let linkGradientBottom = NSColor.dynamic(light: NSColor(rgb: 0xF2F2F7), dark: NSColor(rgb: 0x1C1C1E))

    /// The header band of an item with no source application colour, and of a gray pinboard.
    static let headerDefault = NSColor.dynamic(light: NSColor(rgb: 0x8E8E93), dark: NSColor(rgb: 0x98989D))
    /// The darkening behind a compact header that floats over an image.
    static let compactHeaderShade = NSColor.black.withAlphaComponent(0.4)

    /// The label colour of a pinboard.
    static func pinboard(_ color: PinboardColor) -> NSColor {
        switch color {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: NSColor(rgb: 0xF2B600)
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: headerDefault
        }
    }

    static func resolved(_ background: CardBackground) -> NSColor {
        switch background {
        case .standard: standardBackground
        case .plainText: plainTextBackground
        case .richTextFallback: fallbackBackground
        case .color(let code): NSColor(code)
        }
    }
}

extension NSColor {
    /// A colour with one value for light appearances and another for dark ones, including their
    /// vibrant and high-contrast variants.
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? dark : light
        }
    }

    /// An opaque sRGB colour from `0xRRGGBB`.
    convenience init(rgb: UInt32) {
        self.init(ColorCode(rawValue: rgb))
    }

    convenience init(_ code: ColorCode) {
        self.init(srgbRed: code.red, green: code.green, blue: code.blue, alpha: code.alpha)
    }
}

nonisolated extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
