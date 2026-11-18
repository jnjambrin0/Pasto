import CoreGraphics

/// Every layout number and duration of the permission windows.
enum PermissionMetrics {
    // MARK: Shared template

    /// The content of the windows that ask for one permission.
    static let windowContentSize = CGSize(width: 544, height: 680)
    static let iconSide: CGFloat = 80
    static let iconBottomSpacing: CGFloat = 8
    static let textMaxWidth: CGFloat = 400
    static let titleBottomSpacing: CGFloat = 4
    static let subtitleBottomSpacing: CGFloat = 28
    static let illustrationCornerRadius: CGFloat = 10
    static let illustrationBottomSpacing: CGFloat = 28
    static let buttonSpacing: CGFloat = 16
    /// Around a button's label, inside the button's own margins.
    static let buttonLabelHorizontalPadding: CGFloat = 8
    /// Between the buttons and the line that may follow them.
    static let footnoteTopSpacing: CGFloat = 16
    static let grantedSymbolPointSize: CGFloat = 64
    /// How long the confirmation stays before the screen finishes.
    static let grantedConfirmationDuration: Duration = .seconds(1)

    // MARK: "Paste to other apps" prompt

    static let promptWidth: CGFloat = 280
    static let promptBlockSpacing: CGFloat = 32
    static let promptBlockInset: CGFloat = 16
    static let promptTextSpacing: CGFloat = 8
    /// Between the two buttons, and between them and the check box.
    static let promptButtonSpacing: CGFloat = 8
    static let promptControlSpacing: CGFloat = 16

    // MARK: Illustrations

    /// The art is 8:5 (the safe area of the generated pictures): 400 pt wide in the permission
    /// windows, 280 pt in the prompt.
    static let illustrationSize = CGSize(width: 400, height: 250)
    static let promptIllustrationHeight: CGFloat = 175
}
