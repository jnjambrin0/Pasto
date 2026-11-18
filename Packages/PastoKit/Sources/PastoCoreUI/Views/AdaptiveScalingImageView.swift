import AppKit
import PastoUI

/// Shows an image either filling the view, cropped, or fitted inside it, depending on how close
/// their shapes are (`ImageScaling`).
///
/// The image is the contents of a child layer that is only moved and resized, so nothing is
/// redrawn when the card changes size.
final class AdaptiveScalingImageView: CardView {
    /// The image card's ratio; the link preview lowers it.
    static let defaultScaleToFillRatio: CGFloat = 0.8

    var image: CGImage? {
        didSet {
            imageView.layer?.contents = image
            needsLayout = true
        }
    }

    /// See `ImageScaling.mode(imageSize:viewSize:scaleToFillRatio:)`.
    var scaleToFillRatio = AdaptiveScalingImageView.defaultScaleToFillRatio {
        didSet {
            if scaleToFillRatio != oldValue { needsLayout = true }
        }
    }

    private let imageView = LayerBackedView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        imageView.layer?.contentsGravity = .resize
        imageView.layer?.minificationFilter = .trilinear
        addSubview(imageView)
    }

    override func layout() {
        super.layout()
        guard let image else { return }
        imageView.frame = ImageScaling.imageRect(
            imageSize: CGSize(width: image.width, height: image.height),
            viewSize: bounds.size,
            scaleToFillRatio: scaleToFillRatio
        )
    }
}
