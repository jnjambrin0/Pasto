import CoreGraphics

/// Every number of the onboarding and permission illustrations.
package enum IllustrationMetrics {
    /// The proportion every illustration is shown at: the safe area of the generated pictures
    /// (1280 × 800 of their 1536 × 1024 canvas), which the import keeps whole.
    package static let aspectRatio: CGFloat = 8.0 / 5.0
    /// The vector fallbacks are drawn in this space and scaled to fill the frame; it is also the
    /// @1x size the generated pictures are imported at.
    package static let designSize = CGSize(width: 400, height: 250)
    package static let cornerRadius: CGFloat = 10

    /// In dark mode the generated pictures, which only exist in a light version, are dimmed by a
    /// black veil of this opacity…
    package static let darkVeilOpacity = 0.12
    /// …and outlined by a hairline of the label colour, so the light card sits in the dark window
    /// as a framed picture instead of a glaring hole. In light mode the hairline is fainter.
    package static let darkBorderOpacity = 0.16
    package static let lightBorderOpacity = 0.07
    package static let borderWidth: CGFloat = 1
}
