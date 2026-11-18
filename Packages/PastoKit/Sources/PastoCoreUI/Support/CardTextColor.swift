import AppKit

/// The colours of a card's labels, as values a layout table can hold and compare.
nonisolated enum CardTextColor: Sendable, Hashable {
    /// White at the given opacity: text over a header band or over the compact header's shade.
    case white(alpha: Double)
    case primary
    case secondary
}

extension CardTextColor {
    var color: NSColor {
        switch self {
        case .white(let alpha): NSColor.white.withAlphaComponent(alpha)
        case .primary: CardColor.primaryText
        case .secondary: CardColor.secondaryText
        }
    }
}
