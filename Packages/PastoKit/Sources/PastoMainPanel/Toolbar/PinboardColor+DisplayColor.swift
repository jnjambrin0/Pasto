import AppKit
import PastoCore

extension PinboardColor {
    /// The colour a pinboard's dot and menu swatch are drawn with.
    ///
    /// Seven of the eight are the system colours, which is why they change slightly between light
    /// and dark. Yellow is darker than the system's.
    var displayColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: Self.yellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }

    /// The same in light and dark mode.
    private static let yellow = NSColor(srgbRed: 242 / 255, green: 182 / 255, blue: 0, alpha: 1)
}
