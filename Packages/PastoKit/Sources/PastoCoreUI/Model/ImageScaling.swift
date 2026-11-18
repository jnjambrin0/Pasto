import CoreGraphics

/// Decides whether an image fills its frame, cropped, or fits inside it, whole: it only fills
/// when its shape is close enough to the frame's that little is lost.
nonisolated enum ImageScaling {
    enum Mode: Sendable, Equatable {
        case fill
        case fit
    }

    /// How alike two aspect ratios are, from 0 to 1 (identical).
    static func similarity(imageSize: CGSize, viewSize: CGSize) -> CGFloat {
        let imageRatio = imageSize.width / imageSize.height
        let viewRatio = viewSize.width / viewSize.height
        return 1 - abs(imageRatio - viewRatio) / max(imageRatio, viewRatio)
    }

    /// `scaleToFillRatio` is the similarity from which the image fills: 0 always fills.
    static func mode(imageSize: CGSize, viewSize: CGSize, scaleToFillRatio: CGFloat) -> Mode {
        scaleToFillRatio <= similarity(imageSize: imageSize, viewSize: viewSize) ? .fill : .fit
    }

    /// Where the image is drawn inside a view of `viewSize`: centred, on whole points. There is no
    /// upper bound on the scale, so small images are enlarged.
    static func imageRect(imageSize: CGSize, viewSize: CGSize, scaleToFillRatio: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return .zero }

        // Filling pins the axis on which the image is relatively shorter; fitting, the other one.
        // The pinned side takes the view's length exactly, so rounding never moves it.
        let isImageWider = imageSize.width / imageSize.height > viewSize.width / viewSize.height
        let isFilling = mode(imageSize: imageSize, viewSize: viewSize, scaleToFillRatio: scaleToFillRatio) == .fill
        let size = isImageWider == isFilling
            ? CGSize(width: viewSize.height * imageSize.width / imageSize.height, height: viewSize.height)
            : CGSize(width: viewSize.width, height: viewSize.width * imageSize.height / imageSize.width)
        let origin = CGPoint(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2)
        return CGRect(origin: origin, size: size).integral
    }
}
