import CoreGraphics

/// Dimensions of the link card.
nonisolated enum LinkCellMetrics {
    /// How alike the preview image's shape and the preview area's must be for the image to fill
    /// it. The compact density uses 0: the image always fills.
    static let scaleToFillRatio: CGFloat = 0.7

    static let iconSide: CGFloat = 42
    static let iconCornerRadius: CGFloat = 12
    /// How far below the centre the icon sits in the compact density, clear of the header.
    static let compactIconOffset: CGFloat = 5

    static let footerVerticalPadding: CGFloat = 10
    /// Gap between the title and the URL.
    static let footerSpacing: CGFloat = 3
}
