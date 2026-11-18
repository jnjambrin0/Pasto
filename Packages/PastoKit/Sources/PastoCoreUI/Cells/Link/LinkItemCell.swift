import AppKit
import PastoUI

/// The card of a link: a preview of the page above its title and address.
///
/// The preview shows the page's image when it has one, the site's icon otherwise, and a generic
/// symbol until the metadata arrives. A square image is taken for an icon. With link previews
/// turned off the card is only text.
public final class LinkItemCell: ItemCell {
    /// Preview images are decoded no larger than this; the largest card is 312 pt wide.
    private static let maximumImagePixelSize = 1024

    private let previewView = LinkPreviewView(frame: .zero)
    private let footerView = LinkFooterView(frame: .zero)
    private let artworkRequest = ImageRequest()

    private var isPreviewEnabled = true
    /// A page image wide or tall enough to fill the preview, as opposed to an icon.
    private var showsFullImage = false

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bodyView.addSubview(previewView)
        bodyView.addSubview(footerView)
    }

    override var isCompactContentFullSize: Bool { isPreviewEnabled }

    /// Over a page image the compact header needs its shade; over the gradient it does not.
    override var preferredCompactHeaderStyle: HeaderLayout.CompactStyle? {
        guard isPreviewEnabled else { return nil }
        return showsFullImage ? .gradient : .transparent
    }

    override func configureContent(with model: ItemCellModel, environment: ItemCellEnvironment) {
        isPreviewEnabled = environment.isLinkPreviewsEnabled
        previewView.isHidden = !isPreviewEnabled

        guard case .link(let link) = model.content else {
            showsFullImage = false
            artworkRequest.cancel()
            previewView.artwork = .placeholder
            return
        }
        footerView.configure(title: link.title, url: link.url, isPreviewEnabled: isPreviewEnabled)
        showsFullImage = isPreviewEnabled && link.image.map { !$0.isSquare } == true
        if isPreviewEnabled {
            loadArtwork(for: link, with: environment.imageDecoder)
        } else {
            artworkRequest.cancel()
        }
    }

    /// The page's image, else the site's icon, else a symbol. An image or icon that cannot be
    /// decoded counts as none.
    private func loadArtwork(for link: ItemCellModel.Link, with decoder: ImageDecoder) {
        guard let image = link.image else {
            loadIcon(link.iconData, with: decoder)
            return
        }
        let isIcon = image.isSquare
        let preview = previewView
        artworkRequest.load(
            image.data, maxPixelSize: isIcon ? iconPixelSize : Self.maximumImagePixelSize, with: decoder
        ) { [weak self] state in
            switch state {
            case .loading: preview.artwork = .placeholder
            case .loaded(let decoded): preview.artwork = isIcon ? .icon(decoded) : .image(decoded)
            case .failed: self?.imageDidNotDecode(link, with: decoder)
            }
        }
    }

    private func imageDidNotDecode(_ link: ItemCellModel.Link, with decoder: ImageDecoder) {
        if showsFullImage {
            showsFullImage = false
            compactHeaderStyleDidChange()
        }
        loadIcon(link.iconData, with: decoder)
    }

    private func loadIcon(_ iconData: Data?, with decoder: ImageDecoder) {
        let preview = previewView
        guard let iconData else {
            artworkRequest.cancel()
            preview.artwork = .placeholder
            return
        }
        artworkRequest.load(iconData, maxPixelSize: iconPixelSize, with: decoder) { state in
            switch state {
            case .loading: preview.artwork = .placeholder
            case .loaded(let icon): preview.artwork = .icon(icon)
            case .failed: preview.artwork = .placeholder
            }
        }
    }

    private var iconPixelSize: Int {
        Int(LinkCellMetrics.iconSide * (window?.backingScaleFactor ?? 2))
    }

    override func cancelPendingWork() {
        artworkRequest.cancel()
    }

    // MARK: - Density

    private static func iconOffset(for sizeClass: SizeClass) -> CGFloat {
        sizeClass == .compact ? LinkCellMetrics.compactIconOffset : 0
    }

    private static func scaleToFillRatio(for sizeClass: SizeClass) -> CGFloat {
        sizeClass == .compact ? 0 : LinkCellMetrics.scaleToFillRatio
    }

    override func applyContentLayout(for sizeClass: SizeClass) {
        previewView.iconOffset = Self.iconOffset(for: sizeClass)
        previewView.scaleToFillRatio = Self.scaleToFillRatio(for: sizeClass)
    }

    override func transitionContent(to destination: SizeClass, progress: Double) {
        previewView.iconOffset = previewView.iconOffset.approaching(Self.iconOffset(for: destination), progress: progress)
        previewView.scaleToFillRatio = Self.scaleToFillRatio(for: destination)
    }

    // MARK: - Layout

    /// The footer is as tall as its text and the preview takes the rest. Without previews the
    /// footer is the whole body.
    override func layoutContent(in bounds: CGRect) {
        guard isPreviewEnabled else {
            footerView.frame = bounds
            return
        }
        let footerHeight = min(footerView.fittingHeight(forWidth: bounds.width), bounds.height)
        previewView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - footerHeight)
        footerView.frame = CGRect(x: 0, y: bounds.height - footerHeight, width: bounds.width, height: footerHeight)
    }
}
