import Foundation

/// Dimensions of a card's frame, selection ring and shadow.
nonisolated enum BaseCellMetrics {
    static let cornerRadius: CGFloat = 16
    /// How far the selection ring sticks out around the card. The ring is a view behind the card,
    /// so this is also its visible width.
    static let selectionOutset: CGFloat = 4
    static let selectionCornerRadius: CGFloat = 20
    /// The ring's fade between blue and grey when the strip gains or loses keyboard focus, with
    /// an ease-out curve. It takes as long both ways.
    static let focusFadeDuration: TimeInterval = 0.25

    static let shadowAlpha: CGFloat = 0.08
    static let shadowBlurRadius: CGFloat = 2
}
