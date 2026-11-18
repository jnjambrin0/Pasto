import AppKit

/// The title of a card, which the user can rename in place.
///
/// Editing looks like not editing: same font and colour, no box, no focus ring. A click on the
/// title of a card that is already selected starts it; Return, Tab or losing focus commits;
/// Escape restores the previous title.
final class TitleLabel: NSView, NSTextFieldDelegate {
    /// Whether a click starts editing. The cell allows it only while it is selected; revoking it
    /// in the middle of an edit commits what has been typed.
    var isEditable = false {
        didSet {
            if !isEditable { commitEditing() }
        }
    }

    /// Receives the text when an edit is committed, even if it did not change.
    var onCommitEditing: ((String) -> Void)?
    /// Called when an edit starts or ends, because the field takes all the room while editing.
    var onEditingChange: (() -> Void)?

    private(set) var isEditing = false

    private let textField = NSTextField(string: "")
    private var originalText = ""
    private var placeholder = ""
    /// Whoever had keyboard focus before the edit gets it back afterwards, so the strip keeps
    /// responding to the arrow keys.
    private weak var previousResponder: NSResponder?

    init() {
        super.init(frame: .zero)
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.alignment = .natural
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.allowsExpansionToolTips = true
        textField.allowsDefaultTighteningForTruncation = true
        textField.delegate = self
        addSubview(textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TitleLabel is created in code")
    }

    override var isFlipped: Bool { true }

    // MARK: - Content

    /// Shows `text`. An edit in progress survives a refresh with the same title and is abandoned
    /// otherwise: the cell now shows something else.
    func setText(_ text: String, placeholder: String) {
        if isEditing, text == originalText, placeholder == self.placeholder { return }
        cancelEditing()
        self.placeholder = placeholder
        textField.stringValue = text
    }

    func setFont(_ font: CardFont, color: NSColor) {
        textField.font = font.font
        textField.textColor = color
    }

    /// The size the title needs: its text plus the field's slack (`HeaderMetrics.titleSlack`).
    var fittingTextSize: CGSize {
        let size = textField.intrinsicContentSize
        return CGSize(width: size.width + HeaderMetrics.titleSlack, height: size.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let isChange = newSize != frame.size
        super.setFrameSize(newSize)
        if isChange { needsLayout = true }
    }

    override func layout() {
        super.layout()
        textField.setAlignmentRect(bounds)
    }

    // MARK: - Editing

    func beginEditing() {
        guard isEditable, !isEditing, let window else { return }
        originalText = textField.stringValue
        previousResponder = window.firstResponder
        isEditing = true

        let color = textField.textColor ?? .labelColor
        textField.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: color.withAlphaComponent(HeaderMetrics.placeholderAlpha),
            .font: textField.font as Any,
        ])
        textField.isEditable = true
        onEditingChange?()

        // On the next turn of the run loop, once the click that started the edit is done with.
        Task { [weak self] in
            guard let self, isEditing, let window = self.window else { return }
            window.makeFirstResponder(textField)
            (textField.currentEditor() as? NSTextView)?.insertionPointColor = color
        }
    }

    /// Ends the edit and reports the text. Does nothing if no edit is in progress.
    func commitEditing() {
        guard isEditing else { return }
        isEditing = false
        let text = textField.stringValue
        textField.isEditable = false
        releaseFirstResponder()
        onEditingChange?()
        onCommitEditing?(text)
    }

    /// Ends the edit and puts the previous title back, without reporting anything.
    func cancelEditing() {
        guard isEditing else { return }
        isEditing = false
        textField.abortEditing()
        textField.stringValue = originalText
        textField.isEditable = false
        releaseFirstResponder()
        onEditingChange?()
    }

    private func releaseFirstResponder() {
        Task { [weak self] in
            guard let self, !isEditing, let window = self.window else { return }
            restoreFirstResponder(in: window)
        }
    }

    /// Gives the keyboard back to whoever had it before the edit, unless something else has
    /// taken it meanwhile.
    private func restoreFirstResponder(in window: NSWindow) {
        let hasFocus = textField.currentEditor() != nil || window.firstResponder === textField || window.firstResponder === window
        if hasFocus { window.makeFirstResponder(previousResponder) }
    }

    /// A card that leaves the window in the middle of an edit — recycled while the strip
    /// scrolls, or on a reload — commits it there and then, and hands the keyboard back while
    /// it can still reach the window: on the next turn there is none to give it back in.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, isEditing, let window else { return }
        commitEditing()
        restoreFirstResponder(in: window)
    }

    // MARK: - Events

    /// Outside an edit the inner field must not see clicks: they either start the edit or
    /// belong to the card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isEditing else { return super.hitTest(point) }
        return frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if isEditable, !isEditing {
            beginEditing()
        } else {
            super.mouseDown(with: event)
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelEditing()
        return true
    }
}
