import CoreGraphics

/// The shortcut recorder field.
nonisolated enum ShortcutRecorderMetrics {
    /// The width is the least the field takes: a longer text widens it.
    static let size = CGSize(width: 120, height: 24)
    static let cornerRadius: CGFloat = 6
    static let borderWidth: CGFloat = 1
    static let labelLeadingPadding: CGFloat = 16
    /// Leaves room for the clear button, which sits over the field's trailing end.
    static let labelTrailingPadding: CGFloat = 24
    static let clearButtonSide: CGFloat = 24
    static let clearButtonOpacity = 0.85
    static let clearButtonPressedOpacity = 0.5
}
