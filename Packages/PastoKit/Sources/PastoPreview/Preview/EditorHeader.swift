import AppKit
import PastoUI

/// The header of an editor: Cancel (Esc) on one side, the primary action (⌘S) on the other,
/// the editor's own controls in the middle and, for text, Writing Tools next to the primary
/// action. The New Text Item window uses it too, with "Create" as its primary action.
final class EditorHeader: NSView {
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    var canCommit: Bool {
        get { commitButton.isEnabled }
        set { commitButton.isEnabled = newValue }
    }

    /// Writing Tools is only offered for text, and only when the system has it.
    var showsWritingTools = true {
        didSet { writingToolsButton?.isHidden = !showsWritingTools }
    }

    private let cancelButton = PreviewButton(title: PreviewStrings.cancel)
    private let commitButton: PreviewButton
    private let writingToolsButton = WritingTools.makeButton()
    private var toolbar: NSView?

    init(commitTitle: String, commitToolTip: String) {
        commitButton = PreviewButton(title: commitTitle)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        cancelButton.toolTip = PreviewStrings.discardChanges
        cancelButton.keyEquivalent = KeyEquivalent("\u{1B}", modifiers: [])
        cancelButton.onClick = { [weak self] _ in self?.onCancel?() }

        commitButton.isPrimary = true
        commitButton.toolTip = commitToolTip
        commitButton.keyEquivalent = KeyEquivalent("s", modifiers: .command)
        commitButton.onClick = { [weak self] _ in self?.onCommit?() }

        let margin = PreviewMetrics.editorHeaderMargin
        [cancelButton, commitButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            commitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            commitButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if let writingToolsButton {
            addSubview(writingToolsButton)
            NSLayoutConstraint.activate([
                writingToolsButton.trailingAnchor.constraint(equalTo: commitButton.leadingAnchor, constant: -margin),
                writingToolsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorHeader is created in code")
    }

    /// Puts the editor's own controls in the middle of the header, or takes them away.
    func setToolbar(_ newToolbar: NSView?) {
        toolbar?.removeFromSuperview()
        toolbar = newToolbar
        guard let newToolbar else { return }

        newToolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newToolbar)
        let margin = PreviewMetrics.editorHeaderMargin
        // Centred when there is room; otherwise wherever the buttons leave it.
        let centered = newToolbar.centerXAnchor.constraint(equalTo: centerXAnchor)
        centered.priority = .defaultLow
        NSLayoutConstraint.activate([
            centered,
            newToolbar.centerYAnchor.constraint(equalTo: centerYAnchor),
            newToolbar.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor, constant: margin),
            newToolbar.trailingAnchor.constraint(
                lessThanOrEqualTo: (writingToolsButton ?? commitButton).leadingAnchor, constant: -margin
            ),
        ])
    }
}
