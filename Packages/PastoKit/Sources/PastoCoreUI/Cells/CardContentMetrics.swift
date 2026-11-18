import Foundation

/// Dimensions shared by the bodies of the cards.
nonisolated enum CardContentMetrics {
    /// Inset of the content from the card's leading and trailing edges.
    static let sideInset: CGFloat = 12
    /// Gap between the header and the content below it.
    static let topInset: CGFloat = 10
    /// Gap between the last line of a caption and the card's bottom edge.
    static let bottomInset: CGFloat = 10
    /// Duration of the fade that hides or shows a part of the content during a density change,
    /// with an ease-out curve. The text card's opaque band changes its height over the same time,
    /// which is also the system's default animation duration.
    static let fadeDuration: TimeInterval = 0.25
}
