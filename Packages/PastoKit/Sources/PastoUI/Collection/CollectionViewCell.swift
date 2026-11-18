import AppKit

/// Base class for the cells of a `CollectionView`. Cells are recycled: one instance shows many
/// different items over its lifetime.
///
/// Override `prepareForReuse()` (inherited from `NSView`) to drop anything tied to the item the
/// cell was showing; the collection calls it when the cell goes back to the reuse queue.
open class CollectionViewCell: LayerBackedView {
    public var isSelected = false {
        didSet {
            if isSelected != oldValue { selectionDidChange() }
        }
    }

    /// False while the collection is not the first responder, so cells can show a muted
    /// selection (for instance while the user types in the search field).
    public var isEmphasized = true {
        didSet {
            if isEmphasized != oldValue { selectionDidChange() }
        }
    }

    override public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    /// Called when `isSelected` or `isEmphasized` changes.
    open func selectionDidChange() {}

    // MARK: - Accessibility

    // Each cell is one element of the collection's list, selected like the cell itself, and the
    // keyboard focus while it is selected and the collection has the keys. Subclasses give it
    // its label.

    override open func isAccessibilityElement() -> Bool { true }

    override open func accessibilityRole() -> NSAccessibility.Role? { .group }

    override open func isAccessibilitySelected() -> Bool { isSelected }

    override open func isAccessibilityFocused() -> Bool { isSelected && isEmphasized }

    // What VoiceOver can do with the cell comes from its collection's delegate: pressing it, its
    // own actions and its context menu.

    private var collection: CollectionView? {
        accessibilityParent() as? CollectionView
    }

    override open func accessibilityPerformPress() -> Bool {
        collection?.accessibilityPerformPress(on: self) ?? false
    }

    override open func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        collection?.accessibilityCustomActions(for: self)
    }

    override open func accessibilityPerformShowMenu() -> Bool {
        collection?.accessibilityPerformShowMenu(on: self) ?? false
    }

    /// Returns a recycled cell to a neutral visual state before it is shown again.
    func resetVisualState() {
        alphaValue = 1
        layer?.removeAllAnimations()
        layer?.transform = CATransform3DIdentity
        layer?.opacity = 1
    }
}
