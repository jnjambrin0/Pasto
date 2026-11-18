import CoreGraphics

/// How large a preview opens. `screenSize` is the frame of the main screen, `nil` when there is
/// none.
nonisolated enum PreviewSize {
    /// The size of the whole preview for content of `contentSize`: the content is never smaller
    /// than its minimum, and the header, footer and margins go around it.
    static func viewSize(contentSize: CGSize) -> CGSize {
        CGSize(
            width: max(contentSize.width, PreviewMetrics.minimumContentSize.width) + PreviewMetrics.chromeSize.width,
            height: max(contentSize.height, PreviewMetrics.minimumContentSize.height) + PreviewMetrics.chromeSize.height
        )
    }

    /// The window ⌘E opens from the strip, whatever the item: the content at its minimum, the
    /// header above it and the editing margin below — no footer (390 × 283). The content's own
    /// size is not asked for.
    static var editorWindowSize: CGSize {
        CGSize(
            width: PreviewMetrics.minimumContentSize.width + PreviewMetrics.chromeSize.width,
            height: PreviewMetrics.headerHeight + PreviewMetrics.minimumContentSize.height + PreviewMetrics.editingBottomMargin
        )
    }

    /// Content that has no size of its own: a quarter of the screen each way.
    static func defaultContentSize(screenSize: CGSize?) -> CGSize {
        scaled(screenSize, by: PreviewMetrics.defaultScreenFraction)
    }

    /// Half the screen each way: the size of a files or link preview and the bound of images and
    /// text.
    static func largeContentSize(screenSize: CGSize?) -> CGSize {
        scaled(screenSize, by: PreviewMetrics.largeScreenFraction)
    }

    /// An image at its own size, reduced in proportion to fit half the screen. Never enlarged.
    static func imageContentSize(imageSize: CGSize, screenSize: CGSize?) -> CGSize {
        let bound = largeContentSize(screenSize: screenSize)
        guard imageSize.width > 0, imageSize.height > 0, bound.width > 0, bound.height > 0 else { return imageSize }
        let scale = min(1, bound.width / imageSize.width, bound.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// The box a text is measured in.
    static func textMeasuringBox(screenSize: CGSize?) -> CGSize {
        screenSize == nil ? PreviewMetrics.textFallbackBox : largeContentSize(screenSize: screenSize)
    }

    /// A text as large as it measures plus the editor's insets, within the measuring box.
    static func textContentSize(measuredSize: CGSize, editorInset: CGSize, screenSize: CGSize?) -> CGSize {
        let box = textMeasuringBox(screenSize: screenSize)
        return CGSize(
            width: min(box.width, measuredSize.width + 2 * editorInset.width + PreviewMetrics.textExtraWidth),
            height: min(box.height, measuredSize.height + 2 * editorInset.height)
        )
    }

    private static func scaled(_ size: CGSize?, by fraction: CGFloat) -> CGSize {
        guard let size else { return .zero }
        return CGSize(width: size.width * fraction, height: size.height * fraction)
    }
}
