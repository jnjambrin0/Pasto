import AppKit
import PastoSearch
import PastoUI

/// One row of the suggestions menu: a filter's icon and name, with the part the user typed
/// standing out.
final class SearchSuggestionRowView: LayerBackedView {
    /// The pointer entered (true) or left (false) the row.
    var onHover: ((Bool) -> Void)?
    /// The row was pressed; it acts on mouse down, like a menu item under a held button.
    var onPress: (() -> Void)?

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            showTitle()
            needsDisplay = true
        }
    }

    private let suggestion: SearchSuggestion
    private let iconView: SearchFilterIconView
    private let label = NSTextField(labelWithString: "")

    init(suggestion: SearchSuggestion, icon: SearchFilterIcon) {
        self.suggestion = suggestion
        iconView = SearchFilterIconView(icon: icon)
        super.init(frame: .zero)

        layer?.cornerRadius = SearchMetrics.Suggestions.rowCornerRadius
        layer?.cornerCurve = .continuous
        iconView.isHidden = icon == .none
        addSubview(iconView)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        showTitle()

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    /// The typed part of the title in the primary colour and the rest in the secondary one; a
    /// title nothing was matched against is all primary.
    private func showTitle() {
        let primary = isSelected ? NSColor.white : .labelColor
        let secondary = isSelected
            ? NSColor.white.withAlphaComponent(SearchMetrics.Suggestions.selectedUnmatchedTextOpacity)
            : .secondaryLabelColor
        let ranges = suggestion.matchedRanges
        let title = NSMutableAttributedString(string: suggestion.title, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: ranges.isEmpty ? primary : secondary,
        ])
        for range in ranges {
            title.addAttribute(.foregroundColor, value: primary, range: NSRange(range, in: suggestion.title))
        }
        label.attributedStringValue = title
        label.sizeToFit()
        iconView.tintColor = primary
    }

    /// How far into the row its text starts.
    var textLeadingOffset: CGFloat {
        let metrics = SearchMetrics.Suggestions.self
        return metrics.rowHorizontalPadding + (iconView.isHidden ? 0 : metrics.rowIconSlotSide + metrics.rowSpacing)
    }

    /// The width at which the whole title shows.
    var fittingWidth: CGFloat {
        textLeadingOffset + label.frame.width + SearchMetrics.Suggestions.rowHorizontalPadding
    }

    override func layout() {
        super.layout()
        let metrics = SearchMetrics.Suggestions.self
        let iconInset = (metrics.rowIconSlotSide - metrics.rowIconSide) / 2
        iconView.frame = NSRect(
            x: metrics.rowHorizontalPadding + iconInset,
            y: (bounds.height - metrics.rowIconSide) / 2,
            width: metrics.rowIconSide,
            height: metrics.rowIconSide
        )
        label.frame = NSRect(
            x: textLeadingOffset,
            y: (bounds.height - label.frame.height) / 2,
            width: max(bounds.width - textLeadingOffset - metrics.rowHorizontalPadding, 0),
            height: label.frame.height
        )
    }

    override func updateLayerColors() {
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : nil
    }

    // MARK: - Mouse

    /// The menu's window is never key; the click should act all the same.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }

    // MARK: - Accessibility

    // An item of the suggestions menu, named after its filter, selected as the arrow keys and
    // the pointer select it; its icon and label are inside it.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .menuItem }

    override func accessibilityLabel() -> String? { suggestion.title }

    override func isAccessibilitySelected() -> Bool { isSelected }

    override func accessibilityChildren() -> [Any]? { [] }

    override func accessibilityPerformPress() -> Bool {
        guard let onPress else { return false }
        onPress()
        return true
    }
}
