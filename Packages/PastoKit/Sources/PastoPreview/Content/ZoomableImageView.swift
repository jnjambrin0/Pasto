import AppKit
import VisionKit

/// An image that can be pinched and scrolled, opening fitted to the view or — when smaller than
/// it — at its real size, with the text in it selectable.
final class ZoomableImageView: NSView {
    var image: NSImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            configuredSize = nil
            needsLayout = true
            analyzeText()
        }
    }

    /// Whether the text recognized in the image can be selected. Off while the image is edited.
    var isTextSelectionEnabled = true {
        didSet {
            guard isTextSelectionEnabled != oldValue else { return }
            textOverlay.isHidden = !isTextSelectionEnabled
        }
    }

    private let scrollView = NSScrollView(frame: .zero)
    private let imageView = NSImageView(frame: .zero)
    private let textOverlay = ImageAnalysisOverlayView()
    private var analysis: Task<Void, Never>?
    /// The view size the magnification was last worked out for.
    private var configuredSize: CGSize?

    init() {
        super.init(frame: .zero)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true

        textOverlay.preferredInteractionTypes = .textSelection
        textOverlay.trackingImageView = imageView
        textOverlay.autoresizingMask = [.width, .height]
        imageView.addSubview(textOverlay)

        scrollView.contentView = CenteringClipView(frame: .zero)
        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.drawsBackground = false
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ZoomableImageView is created in code")
    }

    isolated deinit {
        analysis?.cancel()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        configureMagnification()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        configuredSize = nil
        needsLayout = true
    }

    /// The image view always has the size of the view, so that a magnification of 1 means
    /// "fitted". A new size or a new image starts over from the initial zoom.
    private func configureMagnification() {
        guard configuredSize != bounds.size else { return }
        configuredSize = bounds.size

        scrollView.magnification = 1
        imageView.frame = bounds
        textOverlay.frame = imageView.bounds
        guard let image, let magnification = ImageMagnification(imageSize: image.size, viewSize: bounds.size) else { return }
        scrollView.minMagnification = magnification.minimum
        scrollView.maxMagnification = magnification.maximum
        scrollView.magnification = magnification.initial
    }

    private func analyzeText() {
        analysis?.cancel()
        textOverlay.analysis = nil
        guard let image, ImageAnalyzer.isSupported else { return }
        analysis = Task { [weak self] in
            let found = try? await ImageAnalyzer().analyze(image, orientation: .up, configuration: .init(.text))
            guard let self, !Task.isCancelled else { return }
            textOverlay.analysis = found
        }
    }
}

/// Keeps a document smaller than the visible area in its middle instead of in a corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentFrame = documentView?.frame else { return rect }
        if rect.width > documentFrame.width {
            rect.origin.x = documentFrame.midX - rect.width / 2
        }
        if rect.height > documentFrame.height {
            rect.origin.y = documentFrame.midY - rect.height / 2
        }
        return rect
    }
}
