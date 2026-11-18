import AppKit
import PastoUI

/// The rounded, hairline-bordered frame around the content of a preview and around the editor
/// of New Text Item.
final class ContentFrameView: LayerBackedView {
    var borderWidth: CGFloat = 0 {
        didSet { layer?.borderWidth = borderWidth }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = PreviewMetrics.contentCornerRadius
        layer?.masksToBounds = true
    }

    override func updateLayerColors() {
        let base: NSColor = isInDarkMode ? .white : .black
        layer?.borderColor = base.withAlphaComponent(PreviewMetrics.contentBorderOpacity).cgColor
    }
}
