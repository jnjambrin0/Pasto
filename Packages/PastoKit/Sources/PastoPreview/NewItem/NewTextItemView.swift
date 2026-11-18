import AppKit
import PastoCoreUI

/// The content of the New Text Item window: the text editor, empty and ready to type in, under
/// a header with Cancel, the formatting buttons, Writing Tools and Create, and over the counts
/// of what has been typed.
final class NewTextItemView: NSView {
    var onCancel: (() -> Void)?
    /// Called with the text typed, formatting included.
    var onCreate: ((NSAttributedString) -> Void)?

    private let header = EditorHeader(
        commitTitle: PreviewStrings.create, commitToolTip: PreviewStrings.createTextItem
    )
    private let editor = TextEditor()
    private let statisticsContainer = NSStackView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        header.setToolbar(editor.traitBar)
        header.canCommit = false
        header.onCancel = { [weak self] in self?.onCancel?() }
        header.onCommit = { [weak self] in
            guard let self else { return }
            onCreate?(editor.attributedText)
        }

        editor.isEditing = true
        editor.attributedText = NSAttributedString()
        editor.onTextChange = { [weak self] text in self?.textDidChange(text) }
        showStatistics()
        showBackdrop()
        layOut()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NewTextItemView is created in code")
    }

    private func layOut() {
        let editorFrame = ContentFrameView(frame: .zero)
        editorFrame.borderWidth = PreviewMetrics.contentBorderWidth
        editor.autoresizingMask = [.width, .height]
        editorFrame.addSubview(editor)

        for view in [header, editorFrame, statisticsContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let footerInsets = PreviewMetrics.footerInsets
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: PreviewMetrics.headerHeight),
            editorFrame.topAnchor.constraint(equalTo: header.bottomAnchor),
            editorFrame.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewMetrics.contentSideMargin),
            editorFrame.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreviewMetrics.contentSideMargin),
            editorFrame.bottomAnchor.constraint(equalTo: statisticsContainer.topAnchor, constant: -footerInsets.top),
            statisticsContainer.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: PreviewMetrics.newItemFooterSideMargin
            ),
            statisticsContainer.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -PreviewMetrics.newItemFooterBottomMargin
            ),
        ])
    }

    func focusEditor() {
        editor.focus()
    }

    /// The editor's background follows the system mode, like a plain text card's.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        showBackdrop()
    }

    private func showBackdrop() {
        editor.setBackdrop(ItemPresentation.textBackdrop(of: NSAttributedString(), isDark: isInDarkMode))
    }

    /// Any text at all can be created, even one of spaces only.
    private func textDidChange(_ text: NSAttributedString) {
        header.canCommit = !text.string.isEmpty
        showStatistics()
    }

    private func showStatistics() {
        statisticsContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statisticsContainer.addArrangedSubview(editor.makeStatisticsView())
    }
}
