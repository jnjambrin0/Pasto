import AppKit
import PastoCoreUI

/// The text view shared by the preview of text items and the New Text Item window: read-only
/// until told otherwise, always selectable.
///
/// It owns the formatting buttons but does not show them: whoever hosts the editor places
/// `traitBar` in its header.
final class TextEditor: NSView, NSTextStorageDelegate, NSTextViewDelegate {
    /// Called a turn of the run loop after every change of the text or its attributes.
    var onTextChange: ((NSAttributedString) -> Void)?

    let traitBar = TextTraitBar()

    private let scrollView = NSScrollView(frame: .zero)
    private let textView = EditorTextView(frame: .zero)

    init() {
        super.init(frame: .zero)

        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = EditableText.baseFont
        textView.textColor = ItemPresentation.primaryTextColor
        textView.textContainerInset = PreviewMetrics.editorInset
        // Links keep the colours of the text around them.
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = .width
        textView.textStorage?.delegate = self
        textView.delegate = self

        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        addSubview(scrollView)

        traitBar.onToggle = { [weak self] trait in self?.textView.toggle(trait) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextEditor is created in code")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    // MARK: - Content

    var attributedText: NSAttributedString {
        get { NSAttributedString(attributedString: textView.attributedString()) }
        set {
            textView.textStorage?.setAttributedString(newValue)
            // Typing continues the text's last run. An empty text has none, and without
            // attributes of its own the next character would fall back to AppKit's defaults.
            textView.typingAttributes = newValue.length > 0
                ? newValue.attributes(at: newValue.length - 1, effectiveRange: nil)
                : [.font: EditableText.baseFont, .foregroundColor: ItemPresentation.primaryTextColor]
        }
    }

    var isEditing: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    /// See `EditorTextView.copiesTextColors`.
    var copiesTextColors: Bool {
        get { textView.copiesTextColors }
        set { textView.copiesTextColors = newValue }
    }

    /// Sets one font for the whole text.
    func setFont(_ font: NSFont) {
        textView.font = font
    }

    var textInset: CGSize { textView.textContainerInset }

    /// The fill behind the text. The editor takes the appearance that suits it, so that the
    /// primary text colour, the selection and the scroller read well on it.
    func setBackdrop(_ backdrop: ItemPresentation.TextBackdrop) {
        appearance = NSAppearance(named: backdrop.isLight ? .aqua : .darkAqua)
        textView.backgroundColor = backdrop.color
        scrollView.backgroundColor = backdrop.color
    }

    func focus() {
        window?.makeFirstResponder(textView)
    }

    /// The counts of the current text. A snapshot: it does not follow later changes.
    func makeStatisticsView() -> TextStatisticsView {
        TextStatisticsView(text: textView.string)
    }

    // MARK: - Changes

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // Deferred: the storage is still in the middle of its edit and must not be read yet.
        Task { [weak self] in
            guard let self else { return }
            refreshTraitBar()
            onTextChange?(attributedText)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        refreshTraitBar()
    }

    func textViewDidChangeTypingAttributes(_ notification: Notification) {
        refreshTraitBar()
    }

    private func refreshTraitBar() {
        traitBar.activeTraits = textView.activeTraits
    }
}
