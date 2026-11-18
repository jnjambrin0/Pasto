import Foundation

/// The coach mark's measurements.
public nonisolated enum CoachMarkMetrics {
    public static let width: CGFloat = 288
    public static let cornerRadius: CGFloat = 16
    public static let padding: CGFloat = 14
    public static let titleSpacing: CGFloat = 4
    public static let footerSpacing: CGFloat = 10
    public static let buttonSpacing: CGFloat = 6
    public static let titleFontSize: CGFloat = 13
    public static let messageFontSize: CGFloat = 12
    public static let stepFontSize: CGFloat = 11
    /// Between the mark and the element it explains, and from the edges of the window.
    public static let gap: CGFloat = 8
    public static let margin: CGFloat = 12
    /// Coming in: a fade and a short rise, which "Reduce Motion" leaves out; going out, a fade.
    public static let appearDuration: TimeInterval = 0.2
    public static let disappearDuration: TimeInterval = 0.15
    public static let appearDistance: CGFloat = 6
}
