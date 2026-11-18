import AppKit
import PastoCore
import PastoCoreUI

/// The preview of a text item: the whole text in the shared editor, with its counts underneath.
///
/// Reading shows the text as it was copied, fonts and colours included. Editing shows it
/// reduced to what the editor keeps, and saving stores that reduced form.
final class TextContentView: NSView, ItemContentView, FooterProviding, PreferredSizeProviding, EditableContent {
    let footer = FooterView()
    var onCanCommitChange: ((Bool) -> Void)?
    var editingToolbar: NSView? { editor.traitBar }

    private let editor = TextEditor()
    private let environment: PreviewEnvironment
    private let itemID: ItemID

    /// The text as stored.
    private var previewText = NSAttributedString()
    /// The text as the editor takes it, and what an edit is compared against.
    private var editingText = NSAttributedString()

    init(item: Item, environment: PreviewEnvironment) {
        self.environment = environment
        itemID = item.id
        super.init(frame: .zero)

        editor.autoresizingMask = [.width, .height]
        addSubview(editor)
        editor.onTextChange = { [weak self] text in self?.textDidChange(text) }

        loadText()
        showText()
        footer.setContent(editor.makeStatisticsView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextContentView is created in code")
    }

    func update(with item: Item) {
        // What the user is typing wins over a change made elsewhere.
        guard !editor.isEditing else { return }
        loadText()
        showText()
    }

    /// The background rule depends on the system mode, so it is applied again when that changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        showBackdrop()
    }

    // MARK: - Text

    private func loadText() {
        setText(ItemText.text(of: environment.reader.pasteboardItems(for: itemID)?.first))
    }

    private func setText(_ text: NSAttributedString) {
        previewText = text
        editingText = EditableText.normalized(text)
    }

    private func showText() {
        let isPlain = Self.isPlain(previewText)
        // Colours the editor adds to suit its background are not the content's.
        editor.copiesTextColors = !editor.isEditing && !isPlain
        let backdrop = showBackdrop()
        editor.attributedText = readable(editor.isEditing ? editingText : previewText, on: backdrop)
        if isPlain, !editor.isEditing {
            editor.setFont(.preferredFont(forTextStyle: .body))
        }
    }

    /// The same background as the item's card, always worked out from the stored text.
    @discardableResult
    private func showBackdrop() -> NSColor {
        let backdrop = ItemPresentation.textBackdrop(of: previewText, isDark: isInDarkMode)
        editor.setBackdrop(backdrop)
        return backdrop.color
    }

    private static func isPlain(_ text: NSAttributedString) -> Bool {
        var isPlain = true
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, stop in
            if !attributes.isEmpty {
                isPlain = false
                stop.pointee = true
            }
        }
        return isPlain
    }

    /// Text without a colour of its own would be drawn black whatever the background. It takes
    /// the primary text colour, which follows the editor's appearance, or black or white when it
    /// has a background of its own. That choice is made against the backdrop as the editor draws
    /// it, when the text is shown.
    private func readable(_ text: NSAttributedString, on backdrop: NSColor) -> NSAttributedString {
        var background = backdrop
        editor.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = backdrop.usingColorSpace(.deviceRGB) ?? backdrop
        }
        return TextRecoloring.readable(text, on: background, primary: ItemPresentation.primaryTextColor)
    }

    private func textDidChange(_ text: NSAttributedString) {
        footer.setContent(editor.makeStatisticsView())
        if editor.isEditing {
            onCanCommitChange?(canCommit(text))
        }
    }

    /// There is something to save when the text is not empty and differs from the stored one in
    /// characters or in the formatting the editor keeps. An empty text does not delete the item.
    private func canCommit(_ text: NSAttributedString) -> Bool {
        !text.string.isEmpty && !EditableText.normalized(text).isEqual(to: editingText)
    }

    // MARK: - PreferredSizeProviding

    func preferredContentSize(screenSize: CGSize?) -> CGSize {
        let shown = editor.attributedText
        let measuredRange = NSRange(location: 0, length: min(shown.length, PreviewMetrics.textMeasureLimit))
        let measured = shown.attributedSubstring(from: measuredRange).boundingRect(
            with: PreviewSize.textMeasuringBox(screenSize: screenSize),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return PreviewSize.textContentSize(measuredSize: measured.size, editorInset: editor.textInset, screenSize: screenSize)
    }

    // MARK: - EditableContent

    func beginEditing() {
        editor.isEditing = true
        showText()
        onCanCommitChange?(false)
    }

    func cancelEditing() {
        editor.isEditing = false
        showText()
    }

    func commitEditing() {
        editor.isEditing = false
        let edited = EditableText.normalized(editor.attributedText)
        environment.replaceContent(of: itemID, with: ItemContentComposer.text(edited))
        // What the store will hold once the write lands: formatted text, or the bare characters.
        setText(EditableText.hasFormatting(edited) ? edited : NSAttributedString(string: edited.string))
        showText()
    }

    func focusEditor() {
        editor.focus()
    }
}
