import CoreGraphics

/// Every layout number of the About window.
enum AboutMetrics {
    /// The content, laid out under the title bar.
    static let contentSize = CGSize(width: 320, height: 340)
    /// The transparent title bar the content stays clear of: the window measures 320 × 372.
    static let titleBarHeight: CGFloat = 32
    static let inset: CGFloat = 8
    static let spacing: CGFloat = 14
    static let iconSide: CGFloat = 120
    static let nameVersionSpacing: CGFloat = 4
    static let copyrightWidth: CGFloat = 200
    /// Between the copyright line, the warranty line and the Acknowledgements button.
    static let legalSpacing: CGFloat = 6

    // MARK: Acknowledgements window

    static let acknowledgementsSize = CGSize(width: 520, height: 460)
    static let acknowledgementsMinimumSize = CGSize(width: 380, height: 260)
    static let acknowledgementsInset: CGFloat = 20
    static let acknowledgementsEntrySpacing: CGFloat = 24
    static let acknowledgementsLineSpacing: CGFloat = 6
}
