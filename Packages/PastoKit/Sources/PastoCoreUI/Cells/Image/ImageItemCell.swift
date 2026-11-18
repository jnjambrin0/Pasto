import AppKit
import PastoUI

/// The card of an image: the image over a checkerboard, with a capsule that states its size.
///
/// The image fills the card, cropped, only when its shape is within 20 % of the card's;
/// otherwise it is shown whole with the checkerboard around it. Small images are enlarged. In
/// the compact density the image takes the whole card, under a shaded header, and the capsule
/// is not shown.
public final class ImageItemCell: ItemCell {
    private let checkerboardView = CheckerboardView(frame: .zero)
    private let imageView = AdaptiveScalingImageView(frame: .zero)
    private let sizeLabel = ImageSizeLabel(frame: .zero)
    private let thumbnailRequest = ImageRequest()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bodyView.addSubview(checkerboardView)
        bodyView.addSubview(imageView)
        bodyView.addSubview(sizeLabel)
    }

    override var isCompactContentFullSize: Bool { true }
    override var preferredCompactHeaderStyle: HeaderLayout.CompactStyle? { .gradient }

    override func configureContent(with model: ItemCellModel, environment: ItemCellEnvironment) {
        guard case .image(let image) = model.content else {
            thumbnailRequest.cancel()
            imageView.image = nil
            sizeLabel.isHidden = true
            return
        }
        sizeLabel.isHidden = false
        sizeLabel.setSize(width: image.width, height: image.height)

        let imageView = imageView
        thumbnailRequest.load(image.thumbnailData, with: environment.imageDecoder) { state in
            imageView.image = state.image
        }
    }

    override func cancelPendingWork() {
        thumbnailRequest.cancel()
    }

    // MARK: - Density

    private static func sizeLabelAlpha(for sizeClass: SizeClass) -> CGFloat {
        sizeClass == .compact ? 0 : 1
    }

    override func applyContentLayout(for sizeClass: SizeClass) {
        sizeLabel.alphaValue = Self.sizeLabelAlpha(for: sizeClass)
    }

    override func transitionContent(to destination: SizeClass, progress: Double) {
        sizeLabel.alphaValue = sizeLabel.alphaValue.approaching(Self.sizeLabelAlpha(for: destination), progress: progress)
    }

    // MARK: - Layout

    override func layoutContent(in bounds: CGRect) {
        checkerboardView.frame = bounds
        imageView.frame = bounds

        // Centred horizontally, on the row of the shortcut indicator.
        let size = sizeLabel.capsuleSize
        sizeLabel.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: bounds.height - ShortcutIndicatorMetrics.centerFromCardBottom - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
