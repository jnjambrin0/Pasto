import AppKit
import PastoCore
import PastoFoundation

/// The way into the module for the main panel and the app: the preview popover, the editing
/// windows and the New Text Item window.
///
/// Create one at launch and keep it. Nothing here touches the main panel: what the preview needs
/// from it arrives through `PreviewHandlers`, and what the panel needs from the preview is the
/// handful of calls below.
public final class ItemPreviewCoordinator {
    private let environment: PreviewEnvironment
    private let windows = PreviewWindowManager()
    private var popover: PreviewPopover?
    private var newItemWindow: UtilityPanel?

    /// - Parameters:
    ///   - writer: Saves edits and creates new text items.
    ///   - itemWriter: The writer of the user's changes to items, whose undo manager is the
    ///     panel's. A rename made in the preview goes through it, as one made on the card does,
    ///     so that ⌘Z undoes it; without it a rename cannot be undone.
    public init(
        reader: StoreReader,
        writer: StoreWriter,
        itemWriter: UndoableWriter? = nil,
        config: ConfigStore,
        handlers: PreviewHandlers
    ) {
        environment = PreviewEnvironment(
            reader: reader, writer: writer, itemWriter: itemWriter, config: config, handlers: handlers
        )
    }

    // MARK: - State

    /// Whether the popover is open. While it is, Esc in the strip closes it and nothing else, and
    /// ⌘C does not copy the selection (`closePreviewAfterCopy()`).
    public var isPreviewVisible: Bool { popover != nil }

    /// Whether a detached preview, an editor or the New Text Item window is open. The user is
    /// then still working in Pasto, so closing the main panel must not hand the focus back to
    /// the application that had it.
    public var hasOpenWindows: Bool {
        windows.count > 0 || newItemWindow != nil
    }

    /// Whether the system can show Writing Tools; the "Writing Tools" entry of a card's menu and
    /// ⇧⌘E only exist when it can.
    public static var isWritingToolsAvailable: Bool { WritingTools.isAvailable }

    // MARK: - Preview

    /// Space on a card, or "Preview" in its menu: closes the popover if it is open, otherwise
    /// opens it for the item, anchored to `anchor` — the card, which must be visible. Beeps
    /// when the item cannot be previewed.
    public func togglePreview(of id: ItemID, anchoredTo anchor: NSView) {
        guard !closePreview() else { return }
        guard anchor.window != nil, let item = environment.reader.item(id) else {
            NSSound.beep()
            return
        }
        openPopover(for: item, anchoredTo: anchor)
    }

    /// The strip's selection moved to another item while the popover is open: the same popover
    /// shows that item instead, at once and without animation, over `card` — or, when its card
    /// is not on screen, where it is. Does nothing while the popover is closed or already shows
    /// the item.
    public func showSelectedItem(_ id: ItemID, anchoredTo card: NSView?) {
        guard let popover, popover.itemID != id,
              let anchor = card ?? popover.anchor, anchor.window != nil,
              let item = environment.reader.item(id)
        else { return }
        // An item is shown in one place: its window gives way to the popover.
        windows.window(for: item.id)?.close()
        let view = ItemPreviewView(item: item, environment: environment)
        connect(view, to: popover)
        popover.show(view, anchoredTo: anchor)
    }

    private func openPopover(for item: Item, anchoredTo anchor: NSView) {
        // An item is shown in one place: its window gives way to the popover.
        windows.window(for: item.id)?.close()

        let view = ItemPreviewView(item: item, environment: environment)
        let popover = PreviewPopover(previewView: view, config: environment.config)
        connect(view, to: popover)
        popover.onWillClose = { [weak self, weak popover] in
            guard let self, let popover, self.popover === popover else { return }
            self.popover = nil
            // AppKit is still closing it; it must outlive this call.
            Task { withExtendedLifetime(popover) {} }
        }
        popover.detachedWindowProvider = { [weak self, weak popover] in
            guard let self, let popover else { return nil }
            return makeWindow(for: popover.previewView.item, closesAfterEditing: false).panel
        }
        self.popover = popover
        popover.show(anchoredTo: anchor)
    }

    /// The preview's close button closes the popover; its Edit button swaps it for a window.
    private func connect(_ view: ItemPreviewView, to popover: PreviewPopover) {
        view.onClose = { [weak popover] in popover?.close() }
        view.editInterceptor = { [weak self, weak popover] in
            guard let self, let popover else { return }
            replaceWithEditor(popover)
        }
    }

    /// Closes the popover: the main panel is closing, or Esc was pressed in the strip.
    ///
    /// - Returns: Whether there was a popover to close.
    @discardableResult
    public func closePreview() -> Bool {
        guard let popover else { return false }
        popover.close()
        return true
    }

    /// ⌘C in the strip while the popover is open. The strip does not copy its selection then:
    /// it lets the key go on its way and calls this, and the popover closes a moment later.
    public func closePreviewAfterCopy() {
        guard let popover else { return }
        Task { [weak popover] in
            try? await Task.sleep(for: PreviewMetrics.closeAfterCopyDelay)
            popover?.close()
        }
    }

    // MARK: - Editing

    /// ⌘E, or "Edit" in a card's menu: opens an editing window for each of the items that can
    /// be edited. Beeps when none can.
    public func edit(_ ids: [ItemID]) {
        let items = environment.reader.items(ids).filter { ItemContentKind(item: $0).isEditable }
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        items.forEach(openEditor)
    }

    /// ⇧⌘E, or "Writing Tools" in a card's menu: edits the text items among `ids` and shows
    /// Writing Tools on the editor. Does nothing when the system has none or no item is text.
    public func editWithWritingTools(_ ids: [ItemID]) {
        guard WritingTools.isAvailable else { return }
        let texts = environment.reader.items(ids).filter { ItemContentKind(item: $0) == .text }
        guard !texts.isEmpty else { return }
        texts.forEach(openEditor)
        WritingTools.show(from: nil)
    }

    /// Editing always happens in a window. From the popover, the window takes the popover's
    /// place on screen so that the content seems to stay where it was.
    private func replaceWithEditor(_ popover: PreviewPopover) {
        let item = popover.previewView.item
        let frame = popover.contentScreenFrame
        popover.closeInvisibly()

        let (panel, view) = makeWindow(for: item, closesAfterEditing: true)
        if let frame {
            panel.setFrame(frame, display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        view.beginEditing()
    }

    /// An editor opened straight from the strip: at the editors' size whatever the item,
    /// centred, and stepped away from the centre by the number of windows open, itself included.
    private func openEditor(for item: Item) {
        if popover?.itemID == item.id {
            closePreview()
        }
        let (panel, view) = makeWindow(for: item, closesAfterEditing: true)
        panel.animationBehavior = .documentWindow
        // Laid out for editing first: without its footer, the content fits the editors' size.
        view.beginEditing(focusingEditor: false)
        panel.resizeContent(to: PreviewSize.editorWindowSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        if let screen = panel.screen {
            panel.setFrameOrigin(WindowCascade.origin(
                centeredFrame: panel.frame, screenFrame: screen.frame, windowCount: windows.count
            ))
        }
        view.focusEditor()
    }

    /// A window showing the item, registered as the item's one window.
    ///
    /// - Parameter closesAfterEditing: A window opened to edit closes when the edit ends; a
    ///   preview dragged out of the popover stays, back in reading mode.
    private func makeWindow(for item: Item, closesAfterEditing: Bool) -> (panel: UtilityPanel, view: ItemPreviewView) {
        let view = ItemPreviewView(item: item, environment: environment)
        let panel = UtilityPanel()
        panel.title = closesAfterEditing ? PreviewStrings.editorWindowTitle : PreviewStrings.previewWindowTitle
        panel.setContent(view)
        view.onClose = { [weak panel] in panel?.close() }
        if closesAfterEditing {
            view.onEndEditing = { [weak panel] in panel?.close() }
        }
        windows.register(panel, for: item.id)
        return (panel, view)
    }

    // MARK: - New Text Item

    /// "New Text Item" (⌘N): opens the window to type a new item in, or brings it forward if
    /// it is open already.
    ///
    /// - Parameter list: The list the main panel is showing, which must accept items. The item
    ///   goes to the front of it — on a pinboard, without entering the history — and the panel is
    ///   then asked to show that list. With `nil` the item goes to the history and the panel
    ///   stays as it is.
    public func showNewTextItem(in list: ListID?) {
        if let newItemWindow {
            newItemWindow.makeKeyAndOrderFront(nil)
            return
        }
        let panel = UtilityPanel()
        panel.title = PreviewStrings.newTextItemWindowTitle
        panel.animationBehavior = .documentWindow
        panel.minSize = PreviewMetrics.newItemMinimumSize

        let view = NewTextItemView(frame: NSRect(origin: .zero, size: PreviewMetrics.newItemMinimumSize))
        view.onCancel = { [weak panel] in panel?.close() }
        view.onCreate = { [weak self, weak panel] text in
            panel?.close()
            self?.createItem(from: text, in: list)
        }
        panel.setContent(view)
        // Closed, the window and what was typed in it go: the next ⌘N starts afresh.
        panel.onClose = { [weak self, weak panel] in
            guard let self, let panel, newItemWindow === panel else { return }
            newItemWindow = nil
            // AppKit is still closing it; it must outlive this call.
            Task { withExtendedLifetime(panel) {} }
        }
        newItemWindow = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        view.focusEditor()
    }

    private func createItem(from text: NSAttributedString, in list: ListID?) {
        let snapshots = ItemContentComposer.newTextItem(text)
        Task {
            await environment.createItem(from: snapshots, in: list)
            if let list {
                environment.handlers.showList(list)
            }
        }
    }
}
