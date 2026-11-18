import AppKit

/// The search field's text: a single line of TextKit 2 text that scrolls sideways, plain apart
/// from the filter tokens. Its focus ring is drawn by the scroll view around it
/// (`SearchTextScrollView`).
final class SearchTextView: NSTextView {
    /// The text container never wraps: it is far wider than any query.
    private static let unboundedSize = NSSize(width: 1_000_000, height: 1_000_000)
    /// The only entries of the system's contextual menu that make sense in a search field.
    private static let contextMenuActions: Set<Selector> = [
        #selector(cut(_:)), #selector(copy(_:)), #selector(paste(_:)), #selector(selectAll(_:)),
    ]

    /// False while the search is not active, so that neither Tab nor a click can land here.
    var canAcceptFocus = false

    private let placeholderLabel = NSTextField(labelWithString: SearchStrings.placeholder)

    static func make() -> SearchTextView {
        let textView = SearchTextView(usingTextLayoutManager: true)
        textView.configure()
        return textView
    }

    private func configure() {
        minSize = NSSize(width: 1, height: 1)
        maxSize = Self.unboundedSize
        isHorizontallyResizable = true
        isVerticallyResizable = true
        textContainer?.widthTracksTextView = false
        textContainer?.heightTracksTextView = false
        textContainer?.size = Self.unboundedSize
        textContainer?.lineFragmentPadding = 0
        textContainer?.maximumNumberOfLines = 1
        textContainerInset = NSSize(width: 0, height: SearchMetrics.Field.textVerticalInset)

        isFieldEditor = true
        isEditable = true
        isSelectable = true
        isRichText = false
        drawsBackground = false
        // The field has its own undo, which knows about queries rather than characters.
        allowsUndo = false
        focusRingType = .exterior

        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        contentType = nil

        placeholderLabel.textColor = .placeholderTextColor
        // VoiceOver hears the placeholder as the field's own (see Accessibility).
        placeholderLabel.setAccessibilityElement(false)
        addSubview(placeholderLabel)
        applyTextAttributes()
    }

    // MARK: - Accessibility

    // A text view is a text area to VoiceOver; this one is a search field, named and with the
    // placeholder of one.

    override func accessibilityRole() -> NSAccessibility.Role? { .textField }

    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .searchField }

    override func accessibilityLabel() -> String? { SearchStrings.placeholder }

    override func accessibilityPlaceholderValue() -> String? { SearchStrings.placeholder }

    /// The attributes of typed text. Moving the cursor next to a token would otherwise make the
    /// text view adopt the token's, so they are set again after every edit and selection change.
    static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.labelColor]
    }

    func applyTextAttributes() {
        typingAttributes = Self.textAttributes
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        updatePlaceholder()
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !string.isEmpty
        placeholderLabel.sizeToFit()
        let origin = textContainerOrigin
        placeholderLabel.setFrameOrigin(NSPoint(
            x: origin.x + SearchMetrics.Field.placeholderLeadingOffset,
            y: origin.y
        ))
    }

    // MARK: - Focus

    override var acceptsFirstResponder: Bool { canAcceptFocus }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        // Shows the insertion point where it was left.
        setSelectedRange(selectedRange())
        return true
    }

    // MARK: - Menus

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        for item in menu.items where item.action.map(Self.contextMenuActions.contains) != true {
            menu.removeItem(item)
        }
        return menu
    }

    /// A single line has no orientation to change.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        item.action != #selector(changeLayoutOrientation(_:)) && super.validateUserInterfaceItem(item)
    }
}
