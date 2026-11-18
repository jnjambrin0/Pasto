import AppKit
import PastoCoreUI
import PastoInput
import PastoUI

/// The strip of clipboard items: a `CollectionView` plus the keys, the dragging rules and the
/// density handling that are specific to items.
public final class ItemCollectionView: CollectionView {
    public struct PasteRequest {
        /// Paste as plain text (the plain-text modifier is held).
        public var plainText = false
        /// Paste into the active app even when the "to active app" setting is off (⌘V in the panel).
        public var forcesDirectPaste = false
        /// Paste the item at this position (0–8) instead of the selection (quick paste).
        public var quickPasteIndex: Int?
    }

    /// What a key asks for. All of them are about the selection, except a quick paste.
    public enum Command {
        /// Return, Enter, ⌘V or a quick-paste shortcut.
        case paste(PasteRequest)
        /// ⌘C; `plainText` when the plain-text modifier is held too.
        case copy(plainText: Bool)
        /// Delete, Backspace or Forward Delete.
        case delete
        /// ⌘O.
        case open
        /// ⌘R, on the item selected last.
        case rename
        /// ⌘E.
        case edit
        /// ⇧⌘E.
        case writingTools
        /// ⌘G: jump to the selected item in the first other list it is in.
        case showInList
        /// The Paste Stack shortcut.
        case createStack
        /// Space, on the item selected last.
        case preview
    }

    public var onCommand: ((Command) -> Void)?
    /// Whether quick paste works although the strip does not have the keyboard focus, which is
    /// the case while the search field has it.
    public var acceptsQuickPasteWithoutFocus: (() -> Bool)?

    /// Modifiers that turn a paste or copy into its plain-text form. Shift by default.
    public var plainTextModifierFlags: NSEvent.ModifierFlags = .shift
    /// Modifiers that, with a digit 1–9, paste the item in that position. Command by default.
    public var quickPasteModifierFlags: NSEvent.ModifierFlags = .command
    /// The shortcut that makes a Paste Stack of the selection; none until the app sets it.
    /// How the context menu shows that shortcut; nil when its key types no character.
    public var createStackKeyEquivalent: KeyEquivalent?
    /// The same shortcut as the strip matches it: by key code, so any key works.
    public var createStackShortcut: (keyCode: Int, modifiers: NSEvent.ModifierFlags)?

    /// Called for ⌘C while it returns true — the preview popover is open. The strip then does
    /// not copy its selection: the key goes on its way and the popover closes shortly after.
    public var copyWhilePreviewing: (() -> Bool)?

    private static let shortcutModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    /// The cards on screen and the row of notice cards blend from one density to the next.
    private lazy var sizeClassTransitionManager = SizeClassTransitionManager(
        sizeClass: SizeClass(cellSide: contentLayout.cellSide),
        hostView: self
    ) { [weak self] in
        guard let self else { return [] }
        let cells = visibleCellsByIndex.values.compactMap { $0 as? any SizeClassTransitionable }
        return cells + (noticeRow.map { [$0] } ?? [])
    }

    public var sizeClass: SizeClass { sizeClassTransitionManager.currentSizeClass }

    /// The notice cards that lead the clipboard history; nil while nobody provides any.
    var noticeRow: NoticeRowView? {
        didSet {
            noticeRow?.onSizeChange = { [weak self] in self?.needsLayout = true }
            noticeRow?.isHidden = !showsNotices
            leadingAccessoryView = noticeRow
            needsLayout = true
        }
    }

    /// The selection changed, by whatever means.
    var onSelectionChange: (() -> Void)?
    /// The user moved over, clicked or typed in the strip while it shows suggestions.
    var onPicksTouched: (() -> Void)?
    /// The cards are hidden by the suggestions wave: the strip is waiting for suggestions and
    /// takes no part in what the user does.
    var isDimmed = false

    private let listPlaceholder = ListPlaceholderView(frame: .zero)
    private var shownCollection = ItemCellContext.Collection.history
    /// Closes the panel once a drag has been outside it for long enough.
    private var dragExitClose: Task<Void, Never>?

    public init() {
        super.init(layoutConfiguration: MainPanelMetrics.stripConfiguration())
        // The only drag the strip takes is one of its own cards, to reorder a pinboard.
        registerForDraggedTypes([ItemDragType.itemID])
        listPlaceholder.isHidden = true
        addSubview(listPlaceholder)
        // Pointer movement counts as using the suggestions.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    /// Places the notice row and starts the items where it ends. The side of a card does not
    /// depend on the leading inset, so the row is sized first and the strip is laid out once.
    override public func layout() {
        var leadingContentWidth: CGFloat = 0
        if let noticeRow, showsNotices {
            noticeRow.cellSide = CollectionContentLayout(
                configuration: layoutConfiguration, boundsSize: bounds.size, cellCount: 0
            ).cellSide
            let size = noticeRow.rowSize
            noticeRow.frame = NSRect(origin: NSPoint(x: 0, y: MainPanelMetrics.stripBottomInset), size: size)
            leadingContentWidth = size.width
        }
        layoutConfiguration = MainPanelMetrics.stripConfiguration(leadingContentWidth: leadingContentWidth)

        super.layout()
        sizeClassTransitionManager.update(to: SizeClass(cellSide: contentLayout.cellSide))
        listPlaceholder.frame = bounds
    }

    // MARK: - What accompanies the cards

    /// The strip has taken in a change of content, or shows another kind of list. An empty
    /// history or pinboard says so, and the history is led by the notice cards; search results
    /// have neither.
    func contentDidChange(showing collection: ItemCellContext.Collection) {
        shownCollection = collection
        let emptyText: String? = switch collection {
        case .history: PanelStrings.emptyHistory
        case .pinboard: PanelStrings.emptyPinboard
        case .search, .picks: nil
        }
        if let emptyText { listPlaceholder.text = emptyText }
        listPlaceholder.isHidden = emptyText == nil || cellCount != 0

        if let noticeRow, noticeRow.isHidden == showsNotices {
            noticeRow.isHidden = !showsNotices
            needsLayout = true
        }
    }

    private var showsNotices: Bool { shownCollection == .history }

    override public func selectionDidChange() {
        super.selectionDidChange()
        onSelectionChange?()
    }

    /// Part of the key view loop whether or not it is showing, so Tab can always come back to it.
    override public var canBecomeKeyView: Bool { true }

    // MARK: - Suggestions

    override public func cellDidAppear(_ cell: CollectionViewCell) {
        if isDimmed { cell.alphaValue = 0 }
    }

    /// While the cards are hidden the strip takes no pointer events at all: no hover, click or
    /// scroll.
    override public func hitTest(_ point: NSPoint) -> NSView? {
        isDimmed ? nil : super.hitTest(point)
    }

    override public func mouseMoved(with event: NSEvent) {
        if !isDimmed { notePicksTouch() }
        super.mouseMoved(with: event)
    }

    /// The hidden cards are not there for VoiceOver either, nor is their menu.
    override public func accessibilityChildren() -> [Any]? {
        isDimmed ? [] : super.accessibilityChildren()
    }

    override public func accessibilitySelectedChildren() -> [Any]? {
        isDimmed ? [] : super.accessibilitySelectedChildren()
    }

    override public func accessibilityPerformShowMenu() -> Bool {
        isDimmed ? false : super.accessibilityPerformShowMenu()
    }

    override public func mouseDown(with event: NSEvent) {
        if !isDimmed { notePicksTouch() }
        super.mouseDown(with: event)
    }

    private func notePicksTouch() {
        if shownCollection == .picks { onPicksTouched?() }
    }

    // MARK: - Keys

    override public func keyDown(with event: NSEvent) {
        // Waiting for suggestions, the strip only moves its selection.
        guard !isDimmed else {
            super.keyDown(with: event)
            return
        }
        notePicksTouch()
        switch event.keyCode {
        case KeyCode.delete, KeyCode.forwardDelete:
            onCommand?(.delete)
        case KeyCode.returnKey, KeyCode.enter:
            guard !selection.isEmpty else { return }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // ⌃Return opens the selection's context menu, for those who cannot right-click.
            if modifiers.intersection(Self.shortcutModifiers) == .control {
                showContextMenuForSelection()
                return
            }
            onCommand?(.paste(PasteRequest(plainText: modifiers.isSuperset(of: plainTextModifierFlags))))
        case KeyCode.space:
            if !selection.isEmpty { onCommand?(.preview) }
        default:
            super.keyDown(with: event)
        }
    }

    /// Shortcuts are matched by the key that types the character on the active keyboard layout
    /// and by exact modifiers.
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        let hasFocus = window?.firstResponder === self
        if !hasFocus, acceptsQuickPasteWithoutFocus?() == true, let request = quickPasteRequest(for: event) {
            onCommand?(.paste(request))
            return true
        }
        // While focus is elsewhere in the panel (the search field) the rest belong to that view.
        guard hasFocus else {
            return super.performKeyEquivalent(with: event)
        }
        guard let command = command(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        if case .copy = command, copyWhilePreviewing?() == true {
            return super.performKeyEquivalent(with: event)
        }
        // Copying and pasting nothing is not worth a callback; the key is still taken.
        switch command {
        case .copy where selection.isEmpty:
            break
        case .paste(let request) where request.quickPasteIndex == nil && selection.isEmpty:
            break
        default:
            onCommand?(command)
        }
        return true
    }

    private func command(for event: NSEvent) -> Command? {
        if let createStackShortcut, Int(event.keyCode) == createStackShortcut.keyCode,
           event.modifierFlags.intersection(Self.shortcutModifiers)
            == createStackShortcut.modifiers.intersection(Self.shortcutModifiers) {
            return .createStack
        }
        if matches(event, "c", .command) { return .copy(plainText: false) }
        if matches(event, "c", plainTextModifierFlags.union(.command)) { return .copy(plainText: true) }
        if matches(event, "e", .command) { return .edit }
        if matches(event, "e", [.command, .shift]) { return .writingTools }
        if matches(event, "o", .command) { return .open }
        if matches(event, "r", .command) { return .rename }
        if matches(event, "v", .command) { return .paste(PasteRequest(forcesDirectPaste: true)) }
        if matches(event, "g", .command) { return .showInList }
        return quickPasteRequest(for: event).map(Command.paste)
    }

    /// Digits 1–9 with the quick-paste modifier paste the item in that position; adding the
    /// plain-text modifier pastes it as plain text. The plain-text variant is looked up first.
    private func quickPasteRequest(for event: NSEvent) -> PasteRequest? {
        for plainText in [true, false] {
            let modifiers = plainText ? quickPasteModifierFlags.union(plainTextModifierFlags) : quickPasteModifierFlags
            for digit in 1...9 where matches(event, Character(String(digit)), modifiers) {
                return PasteRequest(plainText: plainText, quickPasteIndex: digit - 1)
            }
        }
        return nil
    }

    private func matches(_ event: NSEvent, _ character: Character, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        event.modifierFlags.intersection(Self.shortcutModifiers) == modifiers.intersection(Self.shortcutModifiers)
            && LayoutKeyCodes.shared.keyCode(for: character) == event.keyCode
    }

    // MARK: - Dragging

    /// A card dragged out of the panel is on its way to another application: shortly after the
    /// pointer leaves the panel, the panel gets out of the way — giving up activation closes
    /// it — and the application underneath is there to take the drop. Coming back inside before
    /// then keeps it open. A drag that fails out there does not fly back to a closed panel.
    override public func draggingSessionDidMove(_ session: NSDraggingSession, to screenPoint: NSPoint) {
        guard let window else { return }
        guard !window.frame.contains(screenPoint) else {
            dragExitClose?.cancel()
            dragExitClose = nil
            return
        }
        session.animatesToStartingPositionsOnCancelOrFail = false
        guard dragExitClose == nil else { return }
        dragExitClose = Task { [weak self] in
            try? await Task.sleep(for: MainPanelMetrics.dragExitCloseDelay)
            guard let self, !Task.isCancelled else { return }
            dragExitClose = nil
            // Still outside, or dropped outside: the drag has left the panel for good.
            guard let window = self.window, !window.frame.contains(NSEvent.mouseLocation) else { return }
            NSApp.deactivate()
        }
    }
}
