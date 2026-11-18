import AppKit
import PastoCore
import PastoCoreUI
import PastoUI

/// What a preview shows, whichever container it is in — the popover or a window: a header, the
/// content of the item's kind and that content's footer. While editing, the header becomes the
/// editor's and the footer goes away.
///
/// It follows the item in the store: a change shows at once, and a deleted item closes the
/// preview.
final class ItemPreviewView: NSView {
    /// Asks the container to close.
    var onClose: (() -> Void)?
    /// When set, a request to edit is handed over instead of starting here: the popover never
    /// edits, it opens a window that does.
    var editInterceptor: (() -> Void)?
    /// Called after an edit was saved or cancelled.
    var onEndEditing: (() -> Void)?

    private(set) var item: Item
    private let environment: PreviewEnvironment

    private let header = PreviewHeader()
    private let editorHeader = EditorHeader(commitTitle: PreviewStrings.save, commitToolTip: PreviewStrings.saveChanges)
    private let contentFrame = ContentFrameView(frame: .zero)
    private let footerContainer = NSView(frame: .zero)
    private var content: (any ItemContentView)?
    private var contentKind: ItemContentKind
    private var isEditing = false
    /// Whether the item has anything to share; worked out again when its content changes.
    private var canShare = false

    /// The bottom edge of the content: on the footer while reading, near the bottom of the view
    /// while editing. Only one is active at a time.
    private var contentBottomAboveFooter: NSLayoutConstraint?
    private var contentBottomWhileEditing: NSLayoutConstraint?
    /// Collapses the footer area for content that has no footer.
    private var footerCollapse: NSLayoutConstraint?
    private var storeObservation: StoreChangeObservation?

    private static let renameKey = KeyEquivalent("r", modifiers: .command)
    private static let editKey = KeyEquivalent("e", modifiers: .command)
    private static let escapeKey = KeyEquivalent("\u{1B}", modifiers: [])

    init(item: Item, environment: PreviewEnvironment) {
        self.item = item
        self.environment = environment
        contentKind = ItemContentKind(item: item)
        super.init(frame: .zero)

        layOut()
        connectHeaders()
        installContent()
        refreshShareAvailability()
        configureHeader()
        setFrameSize(preferredSize)

        storeObservation = environment.reader.observeChanges { [weak self] in self?.storeDidChange() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ItemPreviewView is created in code")
    }

    /// The size the preview opens at: what the content asks for, or a quarter of the screen,
    /// plus the header, the footer and the margins.
    private var preferredSize: CGSize {
        let screenSize = NSScreen.main?.frame.size
        let contentSize = (content as? any PreferredSizeProviding)?.preferredContentSize(screenSize: screenSize)
            ?? PreviewSize.defaultContentSize(screenSize: screenSize)
        return PreviewSize.viewSize(contentSize: contentSize)
    }

    // MARK: - Layout

    private func layOut() {
        editorHeader.isHidden = true
        for view in [header, editorHeader, contentFrame, footerContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let margin = PreviewMetrics.contentSideMargin
        let aboveFooter = contentFrame.bottomAnchor.constraint(equalTo: footerContainer.topAnchor)
        let whileEditing = contentFrame.bottomAnchor.constraint(
            equalTo: bottomAnchor, constant: -PreviewMetrics.editingBottomMargin
        )
        contentBottomAboveFooter = aboveFooter
        contentBottomWhileEditing = whileEditing
        footerCollapse = footerContainer.heightAnchor.constraint(equalToConstant: 0)

        var constraints = [
            contentFrame.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentFrame.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            contentFrame.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            contentFrame.widthAnchor.constraint(greaterThanOrEqualToConstant: PreviewMetrics.minimumContentSize.width),
            contentFrame.heightAnchor.constraint(greaterThanOrEqualToConstant: PreviewMetrics.minimumContentSize.height),
            aboveFooter,
            footerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        for bar in [header, editorHeader] {
            constraints += [
                bar.topAnchor.constraint(equalTo: topAnchor),
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: trailingAnchor),
                bar.heightAnchor.constraint(equalToConstant: PreviewMetrics.headerHeight),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func connectHeaders() {
        header.onClose = { [weak self] in self?.onClose?() }
        header.onRename = { [weak self] text in self?.rename(to: text) }
        header.onPin = { [weak self] button in self?.showPinMenu(from: button) }
        header.onShare = { [weak self] button in
            guard let self else { return }
            environment.handlers.share(item.id, button)
        }
        header.onEdit = { [weak self] in self?.requestEditing() }
        editorHeader.onCommit = { [weak self] in self?.endEditing(saving: true) }
        editorHeader.onCancel = { [weak self] in self?.endEditing(saving: false) }
    }

    // MARK: - Content

    /// Builds the content view for the item's kind and puts it, and its footer, in place.
    private func installContent() {
        content?.removeFromSuperview()
        footerContainer.subviews.forEach { $0.removeFromSuperview() }

        contentKind = ItemContentKind(item: item)
        let content = ItemContentFactory.makeView(for: item, environment: environment) { [weak self] in
            self?.onClose?()
        }
        self.content = content
        // Content of no known kind is a message, not content: it gets no frame around it.
        contentFrame.borderWidth = contentKind == .unknown ? 0 : PreviewMetrics.contentBorderWidth
        Self.fill(contentFrame, with: content)

        let footer = (content as? any FooterProviding)?.footer
        footerCollapse?.isActive = footer == nil
        if let footer {
            Self.fill(footerContainer, with: footer)
        }
    }

    private static func fill(_ container: NSView, with view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    private func configureHeader() {
        header.configure(
            title: item.title,
            placeholder: ItemPresentation.typeName(of: item),
            pinboardColor: pinboardColor,
            canShare: canShare,
            canEdit: contentKind.isEditable
        )
    }

    private func refreshShareAvailability() {
        canShare = ShareAvailability.canShare(
            item.preview,
            pasteboardItems: environment.reader.pasteboardItems(for: item.id) ?? [],
            isReachable: { (try? URL(fileURLWithPath: $0).checkResourceIsReachable()) == true }
        )
    }

    private var pinboardColor: NSColor? {
        guard let listID = item.listID, case .pinboard(let color) = environment.reader.list(listID)?.attributes else {
            return nil
        }
        return ItemPresentation.color(of: color)
    }

    private func storeDidChange() {
        guard let current = environment.reader.item(item.id) else {
            // Asked once: later writes must not ask again while the container goes away.
            storeObservation = nil
            onClose?()
            return
        }
        guard current != item else { return }
        let contentChanged = current.preview != item.preview
        item = current
        if contentChanged {
            refreshShareAvailability()
        }
        if !isEditing, ItemContentKind(item: current) != contentKind {
            // An edit can turn text into a link or a colour, and the other way round.
            installContent()
        } else {
            content?.update(with: current)
        }
        configureHeader()
    }

    // MARK: - Header actions

    private func rename(to text: String) {
        guard case .set(let title) = TitleEdit(text: text, currentTitle: item.title) else { return }
        environment.setTitle(title, of: item.id)
        // Shown at once; the store confirms it a moment later.
        item.title = title
        configureHeader()
    }

    private func showPinMenu(from button: NSView) {
        guard let menu = environment.handlers.pinMenu(item.id) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -PreviewMetrics.pinMenuOffset), in: button)
    }

    // MARK: - Editing

    private func requestEditing() {
        guard contentKind.isEditable else { return }
        if let editInterceptor {
            editInterceptor()
        } else {
            beginEditing()
        }
    }

    /// Switches to the editor.
    ///
    /// - Parameter focusingEditor: Whether the editor takes the keyboard focus now, which needs
    ///   the view in its window, where it will stay: the colour editor places its panel beside
    ///   the window. Without it, `focusEditor()` does that part later.
    func beginEditing(focusingEditor: Bool = true) {
        guard !isEditing, let editable = content as? any EditableContent else { return }
        header.cancelTitleEditing()
        editorHeader.showsWritingTools = item.type == .text
        editorHeader.setToolbar(editable.editingToolbar)
        editable.onCanCommitChange = { [weak self] canCommit in self?.editorHeader.canCommit = canCommit }
        editable.beginEditing()
        setEditing(true)
        if focusingEditor {
            editable.focusEditor()
        }
    }

    /// Gives the keyboard focus to the editor of an edit begun without it.
    func focusEditor() {
        guard isEditing, let editable = content as? any EditableContent else { return }
        editable.focusEditor()
    }

    /// Saves or drops the changes and goes back to reading. Nothing asks before dropping them.
    private func endEditing(saving: Bool) {
        guard isEditing, let editable = content as? any EditableContent else { return }
        if saving {
            editable.commitEditing()
        } else {
            editable.cancelEditing()
        }
        setEditing(false)
        // A change of kind that arrived during the edit was held back until now.
        if ItemContentKind(item: item) != contentKind {
            installContent()
            configureHeader()
        }
        onEndEditing?()
    }

    private func setEditing(_ editing: Bool) {
        isEditing = editing
        header.isHidden = editing
        editorHeader.isHidden = !editing
        footerContainer.isHidden = editing
        // The one being dropped goes first: both at once cannot be satisfied.
        (editing ? contentBottomAboveFooter : contentBottomWhileEditing)?.isActive = false
        (editing ? contentBottomWhileEditing : contentBottomAboveFooter)?.isActive = true
    }

    // MARK: - Keys

    /// ⌘R renames, ⌘E edits and Esc closes while reading. While editing, Esc and ⌘S belong to
    /// the editor header's buttons, which the default implementation reaches.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isEditing else { return super.performKeyEquivalent(with: event) }
        if Self.renameKey.matches(event) {
            header.beginTitleEditing()
        } else if Self.editKey.matches(event) {
            requestEditing()
        } else if Self.escapeKey.matches(event) {
            header.cancelTitleEditing()
            onClose?()
        } else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
