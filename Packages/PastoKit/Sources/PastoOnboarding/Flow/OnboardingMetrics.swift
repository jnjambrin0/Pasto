import CoreGraphics

/// Every layout number and duration of the onboarding window.
enum OnboardingMetrics {
    // MARK: Window and navigation

    /// Tall enough for every step: an illustration across the top, its text and controls below.
    static let contentSize = CGSize(width: 544, height: 717)
    /// Screens slide in from the trailing edge and out through the leading one, ease in-out.
    static let transitionDuration = 0.3
    /// With "Reduce motion" they cross-fade instead, in this time.
    static let reducedMotionTransitionDuration = 0.2

    // MARK: Shared by the screens

    /// Between what a step shows and its buttons.
    static let buttonsTopSpacing: CGFloat = 28
    /// The illustration fills the width of the window, under the hidden title bar, at the 8:5 the
    /// pictures are imported at (docs/design/onboarding-art.md).
    static let illustrationSize = CGSize(width: 544, height: 340)
    /// Around the text and controls below the illustration.
    static let bodyHorizontalPadding: CGFloat = 40
    static let bodyTopPadding: CGFloat = 20
    static let bodyBottomPadding: CGFloat = 24
    static let titlePointSize: CGFloat = 22
    static let subtitlePointSize: CGFloat = 13
    static let titleBottomSpacing: CGFloat = 6
    /// Between the subtitle and what the step shows below it.
    static let contentTopSpacing: CGFloat = 14
    /// Between a step's content and its footnote, and between those and the buttons.
    static let contentBottomSpacing: CGFloat = 14
    static let buttonSpacing: CGFloat = 12
    /// The width the title and the subtitle may take at most.
    static let textMaxWidth: CGFloat = 464

    // MARK: Cards of rows (Quick Start, permission states)

    static let cardWidth: CGFloat = 464
    static let cardCornerRadius: CGFloat = 10
    /// Of the label colour, as the fill of the card.
    static let cardFillOpacity = 0.04
    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 8
    static let rowTextSpacing: CGFloat = 2
    /// Between a state's symbol and its text.
    static let statusSymbolSpacing: CGFloat = 8
    static let statusSymbolPointSize: CGFloat = 15
    static let sliderWidth: CGFloat = 120
    /// Between the value under the slider and the warning symbol next to it.
    static let sliderValueSymbolSpacing: CGFloat = 4
}
