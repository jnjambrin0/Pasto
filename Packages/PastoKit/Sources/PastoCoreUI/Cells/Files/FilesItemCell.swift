import AppKit

/// The card of copied files.
///
/// One file shows its thumbnail and its full path, cut at the beginning when it does not fit in
/// two lines. Several files show the system's "multiple documents" icon and a fixed caption;
/// their names are not listed. Sizes are never shown.
public final class FilesItemCell: ItemCell {
    private enum Metrics {
        /// Gap between the image and the path below it.
        static let imageBottomSpacing: CGFloat = 12
        static let pathLineLimit = 2
        /// The size the system icon for several files is asked for at.
        static let multipleFilesIconSide: CGFloat = 256
    }

    private let imageView = NSImageView()
    private let pathLabel = HeadTruncatedLabel(font: .callout, color: .secondary, maximumNumberOfLines: Metrics.pathLineLimit)
    private let thumbnailRequest = ImageRequest()

    private static let multipleFilesIcon: NSImage? = {
        let icon = NSImage(named: NSImage.multipleDocumentsName)
        icon?.size = NSSize(width: Metrics.multipleFilesIconSide, height: Metrics.multipleFilesIconSide)
        return icon
    }()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageAlignment = .alignBottom
        imageView.imageScaling = .scaleProportionallyUpOrDown
        bodyView.addSubview(imageView)
        bodyView.addSubview(pathLabel)
    }

    override func configureContent(with model: ItemCellModel, environment: ItemCellEnvironment) {
        guard case .files(let files) = model.content, let firstPath = files.paths.first else {
            thumbnailRequest.cancel()
            imageView.image = nil
            pathLabel.fullText = ""
            return
        }

        if files.paths.count > 1 {
            thumbnailRequest.cancel()
            imageView.image = Self.multipleFilesIcon
            pathLabel.fullText = CardStrings().multipleFiles
        } else {
            pathLabel.fullText = firstPath
            let imageView = imageView
            thumbnailRequest.load(files.thumbnailData, with: environment.imageDecoder) { state in
                imageView.image = state.image.map { NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height)) }
            }
        }
    }

    override func cancelPendingWork() {
        thumbnailRequest.cancel()
    }

    /// The path sits at the bottom, as tall as its text; the image takes the room above it. The
    /// margins are the same in every density.
    override func layoutContent(in bounds: CGRect) {
        let inset = CardContentMetrics.sideInset
        let width = max(bounds.width - 2 * inset, 0)

        let pathHeight = pathLabel.fit(toWidth: width)
        let pathTop = bounds.height - CardContentMetrics.bottomInset - pathHeight
        pathLabel.setAlignmentRect(CGRect(x: inset, y: pathTop, width: width, height: pathHeight))

        let imageTop = CardContentMetrics.topInset
        imageView.frame = CGRect(
            x: inset, y: imageTop, width: width, height: max(pathTop - Metrics.imageBottomSpacing - imageTop, 0)
        )
    }
}
