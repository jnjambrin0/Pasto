import Foundation
import PastoUI

/// Dimensions of the header that do not depend on the density, or do so by a simple table.
nonisolated enum HeaderMetrics {
    /// Leading inset of the labels, and trailing inset of whatever ends inside the header.
    static let sideInset: CGFloat = 12
    /// How far the large application icon sticks out past the header's top, bottom and trailing
    /// edges, where it is clipped.
    static let appIconOverhang: CGFloat = 14
    static let pinboardIconSide: CGFloat = 12
    /// Gap between the title and the date below it. Negative: their boxes overlap by a point.
    static let stackedLabelSpacing: CGFloat = -1
    /// Gap between the title and the date that follows it on the compact density's single line.
    static let inlineLabelSpacing: CGFloat = 0
    /// Height of the shade behind a compact header in the gradient style. It is taller than the
    /// header and reaches down over the content.
    static let gradientHeight: CGFloat = 64
    /// Extra width the title field takes beyond its text.
    static let titleSlack: CGFloat = 4
    /// Opacity of the title's placeholder relative to the title's colour.
    static let placeholderAlpha: CGFloat = 0.6
    /// The labels change between stacked and inline over this time, with an ease-out curve,
    /// outliving the density transition that triggers it.
    static let labelAxisDuration: TimeInterval = 0.3

    static func appIconSide(for sizeClass: SizeClass) -> CGFloat {
        switch sizeClass {
        case .large: 84
        case .regular: 80
        case .small: 76
        case .compact: 20
        }
    }
}
