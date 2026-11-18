import AppKit

/// The fonts cards use. All but one are system text styles, some with another weight at the same
/// size, so they follow the system's sizes: 15 pt for `title3`, 13 pt for `headline` and `body`,
/// 12 pt for `callout`.
nonisolated enum CardFont: Sendable, Hashable {
    case title3Medium
    case headlineSemibold
    case body
    case bodySemibold
    case callout
    /// The hexadecimal value on a colour card.
    case colorCode

    var font: NSFont {
        switch self {
        case .title3Medium: Self.system(.title3, weight: .medium)
        case .headlineSemibold: Self.system(.headline, weight: .semibold)
        case .body: .preferredFont(forTextStyle: .body)
        case .bodySemibold: Self.system(.body, weight: .semibold)
        case .callout: .preferredFont(forTextStyle: .callout)
        case .colorCode: .userFixedPitchFont(ofSize: 18) ?? .monospacedSystemFont(ofSize: 18, weight: .regular)
        }
    }

    private static func system(_ style: NSFont.TextStyle, weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: NSFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
    }
}
