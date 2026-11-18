import AppKit
import PastoUI

/// A symbol button of the search field: the clear button and the filters button.
///
/// A click never takes the keyboard focus, which stays in the text. With "Keyboard navigation"
/// on in System Settings, Tab reaches the button while the search is active, Space or Return
/// presses it and its focus ring is a capsule, as the preview's buttons do.
final class SearchFieldButton: NSButton {
    /// False while the field is out of sight: neither Tab nor assistive technologies reach the
    /// button then.
    var isReachable = false {
        didSet { setAccessibilityElement(isReachable) }
    }

    /// The keyboard focus left the button.
    var onResignFocus: (() -> Void)?

    init(symbol: SymbolDescription, label: String) {
        super.init(frame: .zero)
        image = symbol.makeImage()
        imagePosition = .imageOnly
        isBordered = false
        setAccessibilityLabel(label)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SearchFieldButton is created in code")
    }

    // MARK: - Keyboard

    override var canBecomeKeyView: Bool {
        isReachable && isEnabled && !isHiddenOrHasHiddenAncestor && NSApp.isFullKeyboardAccessEnabled
    }

    /// Only the keyboard gives the button the focus: a click leaves it in the text.
    override var acceptsFirstResponder: Bool {
        canBecomeKeyView && !Self.isMouseDown(NSApp.currentEvent)
    }

    private static func isMouseDown(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        onResignFocus?()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              [" ", "\r"].contains(event.charactersIgnoringModifiers)
        else { return super.keyDown(with: event) }
        performClick(nil)
    }

    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        let radius = min(bounds.width, bounds.height) / 2
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }
}
