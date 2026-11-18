import CoreGraphics

/// The zoom range of an image preview.
///
/// The image view fills the scroll view and scales the image to fit, so a magnification of 1 is
/// "fitted" and `ratio`, the image's size over the view's, is "real size" when below 1.
nonisolated struct ImageMagnification: Equatable {
    let minimum: CGFloat
    let maximum: CGFloat
    /// Fitted for an image larger than the view, real size for a smaller one.
    let initial: CGFloat

    /// `nil` while either size is empty.
    init?(imageSize: CGSize, viewSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return nil }
        let ratio = max(imageSize.width / viewSize.width, imageSize.height / viewSize.height)
        minimum = min(1, ratio)
        maximum = PreviewMetrics.maximumImageScale * ratio
        // Real size for a larger image, 1 / ratio, lies below the minimum, to which the scroll
        // view would raise it anyway: both cases come to this.
        initial = minimum
    }
}
