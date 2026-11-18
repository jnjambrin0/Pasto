import AppKit

/// The tab bar's scrolling area: horizontal only, with no scroller and no background.
final class TabBarScrollView: NSScrollView {
    /// Called whenever the visible part of the content changes.
    var onScroll: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasHorizontalScroller = false
        hasVerticalScroller = false
        verticalScrollElasticity = .none
        drawsBackground = false
        automaticallyAdjustsContentInsets = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabBarScrollView is created in code")
    }

    var contentOffset: CGFloat { contentView.bounds.minX }

    func setContentOffset(_ offset: CGFloat, animated: Bool) {
        let origin = NSPoint(x: offset, y: 0)
        // Bounds changes only animate through the animator proxy.
        (animated ? contentView.animator() : contentView).setBoundsOrigin(origin)
        reflectScrolledClipView(contentView)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onScroll?()
    }
}
