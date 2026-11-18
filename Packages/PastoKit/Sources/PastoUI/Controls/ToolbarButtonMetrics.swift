import CoreGraphics

/// Dimensions and fills of `ToolbarButton`.
nonisolated enum ToolbarButtonMetrics {
    static let regularHeight: CGFloat = 24
    /// A `regular` button is as wide as its content plus this padding on each side…
    static let regularHorizontalPadding: CGFloat = 12
    /// …but never narrower than this.
    static let regularMinimumWidth: CGFloat = 32
    static let mediumSide: CGFloat = 28
    static let largeSide: CGFloat = 32

    /// The fill is the label colour at these opacities; at rest there is none.
    static let hoverFillOpacity: CGFloat = 0.05
    /// `isSelected`.
    static let selectedFillOpacity: CGFloat = 0.10
    static let pressedFillOpacity: CGFloat = 0.15
}
