import AppKit
import PastoCoreUI

/// The item's title in the preview header. A click, or ⌘R, turns it into a text field; ending
/// the edit reports the text, and Esc puts the title back.
final class PreviewTitleField: NSView, NSTextFieldDelegate {
    /// Called with the field's text when an edit ends, however it ends.
    var onCommit: ((String) -> Void)?
    var isEditable = true

    private let textField = NSTextField(labelWithString: "")
    private var title: String?
    private var placeholder = ""
    private var isEditingTitle = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        textField.font = .systemFont(ofSize: NSFont.preferredFont(forTextStyle: .headline).pointSize, weight: .medium)
        textField.textColor = ItemPresentation.primaryTextColor
        textField.alphaValue = PreviewMetrics.titleOpacity
        // Editing changes nothing of the look: no focus ring, and the caret in the text's colour.
        textField.focusRingType = .none
        textField.alignment = .natural
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.allowsExpansionToolTips = true
        textField.allowsDefaultTighteningForTruncation = true
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        // The title gives way to the header's buttons.
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PreviewTitleField is created in code")
    }

    /// - Parameter placeholder: What stands for the title while the item has none.
    func setTitle(_ title: String?, placeholder: String) {
        self.title = title
        self.placeholder = placeholder
        if !isEditingTitle {
            showTitle()
        }
    }

    /// At rest an untitled item reads as its placeholder; in the field, as an empty text with
    /// the placeholder behind it.
    private func showTitle() {
        textField.placeholderString = placeholder
        textField.stringValue = isEditingTitle ? title ?? "" : title ?? placeholder
    }

    // MARK: - Editing

    func beginEditing() {
        guard isEditable, !isEditingTitle else { return }
        isEditingTitle = true
        showTitle()
        textField.isEditable = true
        guard window?.makeFirstResponder(textField) == true else { return }
        (textField.currentEditor() as? NSTextView)?.insertionPointColor = textField.textColor ?? .labelColor
    }

    /// Puts the title back and gives up the focus. Ending the edit still reports the text,
    /// which is then the title the item already has.
    func cancelEditing() {
        guard isEditingTitle else { return }
        showTitle()
        window?.makeFirstResponder(nil)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard isEditingTitle else { return }
        let text = textField.stringValue
        isEditingTitle = false
        textField.isEditable = false
        showTitle()
        onCommit?(text)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelEditing()
        return true
    }

    // MARK: - Mouse

    /// At rest the whole field is one click target; the label inside would swallow the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit != nil && !isEditingTitle ? self : hit
    }

    /// The preview's window moves by its background; a click on the title edits it instead.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }
}
