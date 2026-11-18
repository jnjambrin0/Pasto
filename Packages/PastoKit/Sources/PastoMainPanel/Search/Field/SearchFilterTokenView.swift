import AppKit
import PastoUI

/// A filter inside the search field: a capsule with the filter's icon and name. Clicking it
/// selects it, so that Delete removes it.
final class SearchFilterTokenView: LayerBackedView {
    var onClick: (() -> Void)?

    private let iconView: SearchFilterIconView
    private let label: NSTextField

    init(title: String, icon: SearchFilterIcon) {
        iconView = SearchFilterIconView(icon: icon)
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .labelColor
        label.sizeToFit()
        addSubview(iconView)
        addSubview(label)

        // The token is exactly as large as its content: nothing ever resizes it.
        let metrics = SearchMetrics.Token.self
        let height = label.frame.height + 2 * metrics.verticalPadding
        let width = 2 * metrics.horizontalPadding + metrics.iconSide + metrics.iconToLabelSpacing + label.frame.width
        setFrameSize(NSSize(width: width, height: height))
        layer?.cornerRadius = height / 2
        layer?.cornerCurve = .continuous

        iconView.frame = NSRect(
            x: metrics.horizontalPadding,
            y: (height - metrics.iconSide) / 2,
            width: metrics.iconSide,
            height: metrics.iconSide
        )
        label.setFrameOrigin(NSPoint(x: iconView.frame.maxX + metrics.iconToLabelSpacing, y: metrics.verticalPadding))
    }

    override func updateLayerColors() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(SearchMetrics.Field.fillOpacity).cgColor
    }

    /// The whole capsule is the token: its label never takes the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // MARK: - Accessibility

    // A button named after its filter, which selects the token as a click does; its icon and
    // label are inside it.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? { label.stringValue }

    override func accessibilityChildren() -> [Any]? { [] }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick else { return false }
        onClick()
        return true
    }
}
