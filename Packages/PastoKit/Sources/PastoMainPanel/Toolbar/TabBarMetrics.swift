import AppKit
import PastoInput
import PastoUI

/// Layout values for the tab bar and its cells.
nonisolated enum TabBarMetrics {
    // MARK: Container

    /// Height of the scrolling strip, centred in the toolbar.
    static let scrollHeight: CGFloat = 40
    static let horizontalContentInset: CGFloat = 7
    static let verticalContentInset: CGFloat = 6
    static let cellSpacing: CGFloat = 8
    /// Width of the line at each end that shows there are more tabs on that side.
    static let edgeOverlayWidth: CGFloat = 1
    /// The line is a vertical gradient, clear at both ends and the label colour at this opacity
    /// in the middle.
    static let edgeOverlayOpacity: CGFloat = 0.16
    /// An end's line shows once more than this much content is hidden beyond it.
    static let edgeOverlayThreshold: CGFloat = horizontalContentInset

    /// Scrolling a tab into view, and the other tabs making way for a dragged one, take this long
    /// with the system's ease-out curve. Nothing else in the bar uses it: the capsules change at
    /// once.
    static let revealDuration: TimeInterval = 0.15
    /// The tabs sliding to their new places after tabs come, go, are renamed or recoloured: nil,
    /// the system's default duration (0.25 s), with the ease-out curve.
    static let reflowDuration: TimeInterval? = nil
    /// Room left on each side of a tab scrolled into view.
    static let revealMargin: CGFloat = 24

    // MARK: Cell

    static let cellHeight: CGFloat = scrollHeight - 2 * verticalContentInset
    static let iconLeadingInset: CGFloat = 8
    static let iconToLabelSpacing: CGFloat = 4
    static let labelTrailingInset: CGFloat = 8
    /// The label is this much wider than its text, which starts at the label's leading edge.
    static let labelSlack: CGFloat = 4
    static let maximumLabelWidth: CGFloat = 200
    /// How far inside its frame a text field draws its text. The field is shifted by this much so
    /// that the text starts where the label does.
    static let textFieldPadding: CGFloat = 2

    static let historyIconSide: CGFloat = 18
    static let pinboardIconSide: CGFloat = 16
    /// The dot is smaller than its slot, and has a rim of its own colour, darkened: `PinboardDot`.
    static let pinboardDotDiameter: CGFloat = 12

    /// The size of the label's font, regular weight.
    static let historySymbol = SymbolDescription("clock.arrow.circlepath", pointSize: 13)

    // MARK: Cell background

    // The capsule is the label colour at these opacities; at rest there is none.

    static let hoverFillOpacity: CGFloat = 0.05
    /// Also the fill of a tab that dragged cards are over.
    static let selectedFillOpacity: CGFloat = 0.10
    static let pressedFillOpacity: CGFloat = 0.15
    static let editingFillOpacity: CGFloat = 0.05
    /// Drawn around the capsule, outside it, while its name is being edited.
    static let focusRingWidth: CGFloat = 3

    // MARK: Interaction

    /// How far the pointer travels, in any direction, with the button down before a press
    /// becomes a drag.
    static let dragThreshold: CGFloat = 3
    /// The tab being dragged leaves only its gap behind.
    static let draggedCellOpacity: CGFloat = 0
    /// After a tab is dragged, the app is made active again this long after the drag ends.
    static let reactivationDelay: TimeInterval = 1

    /// ⌘→ and ⌘←, the shortcuts a new installation starts with.
    static let nextPinboardShortcut = Shortcut(keyCode: Int(KeyCode.rightArrow), modifiers: .command)
    static let previousPinboardShortcut = Shortcut(keyCode: Int(KeyCode.leftArrow), modifiers: .command)
}
