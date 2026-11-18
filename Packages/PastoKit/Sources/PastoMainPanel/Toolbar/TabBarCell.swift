import AppKit
import PastoCore
import PastoCoreUI
import PastoUI

/// One tab: an icon and a name inside a capsule that fills in when the tab is selected, under the
/// pointer, pressed or being renamed.
///
/// The cell draws, edits and tells a click from a request to rename or for its menu; the tab bar
/// turns a press into a drag.
final class TabBarCell: LayerBackedView, NSTextFieldDelegate, NSViewToolTipOwner {
    private static let font = NSFont.preferredFont(forTextStyle: .body)

    private(set) var item: TabBarItem

    /// Builds the tab's context menu.
    var menuProvider: (() -> NSMenu?)?
    /// The tab was clicked: the button went up inside it.
    var onSelect: (() -> Void)?
    /// The second press of a double click landed on the name.
    var onBeginRenaming: (() -> Void)?
    /// Called while the name is being edited, whenever what was typed changes the width needed.
    var onPreferredWidthChange: (() -> Void)?
    /// Called when a rename ends, with the new name — trimmed, and possibly empty — or nil when
    /// there is nothing to change.
    var onEndEditing: ((_ newName: String?) -> Void)?
    /// Called when cards of the strip are dropped on the tab, with their items.
    var onDropItems: (([ItemID]) -> Void)?
    /// What the tab says under the pointer, asked for each time the tooltip is about to show:
    /// it counts the list's items, which change while the panel is open. Nil, no tooltip.
    var toolTipProvider: (() -> String?)? {
        didSet { updateToolTipArea() }
    }
    /// False while a tab is being dragged: no tab has a tooltip then.
    var showsToolTip = true {
        didSet {
            if showsToolTip != oldValue { updateToolTipArea() }
        }
    }
    private var toolTipTag: NSView.ToolTipTag?

    private(set) var isSelected = false
    private(set) var isEditing = false

    var isPressed = false {
        didSet {
            if isPressed != oldValue { restyle() }
        }
    }

    /// Reduced to a square holding only the icon. The name goes and comes back at once, outside
    /// the toolbar's transition, and is clipped rather than cut with an ellipsis while the tab
    /// changes width.
    ///
    /// The capsule is not worked out again: a selected tab keeps its fill and shrinks with it to
    /// a circle, until something else restyles the tab — the pointer, a press, the selection.
    /// Only then does "selected and collapsed" count as no capsule: collapsing does not restyle
    /// the cell.
    var isCollapsed = false {
        didSet {
            guard isCollapsed != oldValue else { return }
            label.lineBreakMode = .byClipping
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                label.alphaValue = isCollapsed ? 0 : 1
            }
            // Pasto does restyle on the way back: a tab chosen while collapsed would otherwise
            // come back without its capsule until the pointer moves.
            if !isCollapsed { restyle() }
            needsLayout = true
        }
    }

    private var isHovered = false {
        didSet {
            if isHovered != oldValue { restyle() }
        }
    }
    private var trackingArea: NSTrackingArea?

    /// True while dragged cards are over the tab and it would take them.
    private var isDragDestination = false {
        didSet {
            if isDragDestination != oldValue { restyle() }
        }
    }

    /// The capsule's opacity as of the last restyle. It is what the capsule shows, also when the
    /// appearance changes, until the next restyle.
    private var capsuleOpacity: CGFloat = 0

    /// The capsule is a view of its own because rounding a view's corners makes it clip, and the
    /// focus ring has to show outside the cell.
    private let capsuleView = NSView(frame: .zero)
    private let symbolView = SymbolView()
    private let dotView = NSImageView()
    private let label = NSTextField(frame: .zero)
    private let focusRingView = NSView(frame: .zero)

    init(item: TabBarItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: TabBarMetrics.cellHeight))

        capsuleView.wantsLayer = true
        capsuleView.layer?.cornerRadius = TabBarMetrics.cellHeight / 2
        capsuleView.layer?.cornerCurve = .continuous
        addSubview(capsuleView)

        addSubview(symbolView)

        dotView.imageScaling = .scaleNone
        // Decoration, also while the name is edited and the cell shows VoiceOver its field.
        dotView.setAccessibilityElement(false)
        addSubview(dotView)

        // A plain field made borderless, in the control text colour. A label field, or any in the
        // label colour, is vibrant over the panel's glass: the selection of a name being renamed
        // would then add up with the capsule (`#3F638B` + `#2B2B2B` = `#6A8EB6`) instead of
        // showing the system's selected text background as it is.
        label.isBordered = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.font = Self.font
        label.lineBreakMode = .byTruncatingTail
        label.focusRingType = .none
        label.delegate = self
        addSubview(label)

        focusRingView.wantsLayer = true
        focusRingView.layer?.borderWidth = TabBarMetrics.focusRingWidth
        focusRingView.layer?.cornerRadius = TabBarMetrics.cellHeight / 2 + TabBarMetrics.focusRingWidth
        focusRingView.layer?.cornerCurve = .continuous
        focusRingView.isHidden = true
        addSubview(focusRingView)

        registerForDraggedTypes([ItemDragType.itemID])
        showItem()
    }

    // MARK: - Content

    func update(_ newItem: TabBarItem) {
        guard newItem != item else { return }
        item = newItem
        showItem()
    }

    private func showItem() {
        switch item.kind {
        case .history:
            symbolView.symbol = TabBarMetrics.historySymbol
            symbolView.tintColor = .labelColor
            symbolView.isHidden = false
            dotView.isHidden = true
        case .pinboard:
            symbolView.isHidden = true
            dotView.isHidden = false
        }
        // A name arriving from the store must not replace what the user is typing.
        if !isEditing {
            label.stringValue = item.name
        }
        needsLayout = true
        needsDisplay = true
    }

    private var iconSide: CGFloat {
        switch item.kind {
        case .history: TabBarMetrics.historyIconSide
        case .pinboard: TabBarMetrics.pinboardIconSide
        }
    }

    /// The width the cell needs for its current name, or for what is being typed.
    var preferredWidth: CGFloat {
        if isCollapsed { return TabBarMetrics.cellHeight }
        let text = label.currentEditor()?.string ?? label.stringValue
        let textWidth = NSAttributedString(string: text, attributes: [.font: Self.font]).size().width
        return TabBarLayout.cellWidth(iconSide: iconSide, textWidth: textWidth)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateToolTipArea()
    }

    override func layout() {
        super.layout()
        capsuleView.frame = bounds

        let side = iconSide
        // A collapsed tab centres its icon.
        let slotX = isCollapsed ? (bounds.width - side) / 2 : TabBarMetrics.iconLeadingInset
        let slot = NSRect(x: slotX, y: (bounds.height - side) / 2, width: side, height: side)
        symbolView.frame = slot

        let dot = TabBarMetrics.pinboardDotDiameter
        dotView.frame = NSRect(x: slot.midX - dot / 2, y: slot.midY - dot / 2, width: dot, height: dot)

        // The label's box runs from the end of the icon's gap to the trailing margin. The field
        // itself starts a little earlier, so that its text begins exactly where the box does.
        let boxMinX = slot.maxX + TabBarMetrics.iconToLabelSpacing
        let boxWidth = max(bounds.width - TabBarMetrics.labelTrailingInset - boxMinX, 0)
        label.frame = NSRect(
            x: boxMinX - TabBarMetrics.textFieldPadding,
            y: TabBarMetrics.verticalContentInset,
            width: boxWidth,
            height: bounds.height - 2 * TabBarMetrics.verticalContentInset
        )
        // Back to an ellipsis once the tab has its whole width again: a name longer than a tab
        // may be is cut at its end.
        if !isCollapsed, !isEditing, bounds.width >= preferredWidth - 0.5 {
            label.lineBreakMode = .byTruncatingTail
        }

        focusRingView.frame = bounds.insetBy(dx: -TabBarMetrics.focusRingWidth, dy: -TabBarMetrics.focusRingWidth)
    }

    // MARK: - Appearance

    /// Every change of the capsule is instant, the selection's too: the capsule jumps from one
    /// tab to another. The tab bar sets every tab's selection whenever it changes, and each tab
    /// restyles.
    func setSelected(_ selected: Bool) {
        let didChange = selected != isSelected
        isSelected = selected
        restyle()
        if didChange {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    // MARK: - Accessibility

    // A tab is one radio button of the tab bar's group, named after its list; its icon and
    // colour dot are decoration. While it is being renamed, its field is what VoiceOver reaches.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }

    override func accessibilityLabel() -> String? { item.name }

    override func accessibilityValue() -> Any? { NSNumber(value: isSelected) }

    override func accessibilityChildren() -> [Any]? {
        isEditing ? super.accessibilityChildren() : []
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onSelect else { return false }
        onSelect()
        return true
    }

    /// Works the capsule out again from the tab's state. Every change of state but collapsing
    /// calls it (see `isCollapsed`).
    private func restyle() {
        capsuleOpacity = fillOpacity
        needsDisplay = true
    }

    private var fillOpacity: CGFloat {
        if isEditing {
            TabBarMetrics.editingFillOpacity
        } else if isPressed {
            TabBarMetrics.pressedFillOpacity
        } else if (isSelected && !isCollapsed) || isDragDestination {
            TabBarMetrics.selectedFillOpacity
        } else if isHovered {
            TabBarMetrics.hoverFillOpacity
        } else {
            0
        }
    }

    override func updateLayerColors() {
        // Assigned outside any animation group, so the capsule changes at once.
        let opacity = capsuleOpacity
        capsuleView.layer?.backgroundColor = opacity > 0 ? NSColor.labelColor.withAlphaComponent(opacity).cgColor : nil

        // Drawn again with every change of appearance, which the colours follow.
        if case .pinboard(let color) = item.kind {
            dotView.image = PinboardDot.image(color: color.displayColor, side: TabBarMetrics.pinboardDotDiameter)
        }
        focusRingView.layer?.borderColor = NSColor.keyboardFocusIndicatorColor.cgColor
    }

    // MARK: - Mouse

    /// The whole capsule is the tab, except while its name is being edited: then the text field
    /// needs the clicks to place the insertion point.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return isEditing || hit == nil ? hit : self
    }

    /// The panel can be clicked while it is not key; the click should act, not just focus it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The pointer is followed only while the panel is key. Each time the tab's geometry changes
    /// — it appears, slides, collapses — the area is made anew and the pointer looked for again:
    /// a tab that arrives under a still pointer lights up, none does while a button is down, and
    /// a press is forgotten.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
        isHovered = NSEvent.pressedMouseButtons == 0 && isPointerInside
        isPressed = false
    }

    private var isPointerInside: Bool {
        guard let window else { return false }
        return visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        guard !isEditing else {
            super.mouseDown(with: event)
            return
        }
        if !isCollapsed, event.modifierFlags.contains(.control) {
            if let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
            return
        }
        // Renaming starts on the way down of the second click, and only over the name.
        if !isCollapsed, event.clickCount == 2, label.frame.contains(convert(event.locationInWindow, from: nil)) {
            onBeginRenaming?()
            return
        }
        isPressed = true
        // On to the tab bar, where the press may become a drag.
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard !isEditing else {
            super.mouseUp(with: event)
            return
        }
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onSelect?()
        } else {
            super.mouseUp(with: event)
        }
    }

    /// The tab's icon and name, without its capsule, for the tab bar to drag around.
    func makeDragImage() -> NSImage {
        let backdrop = [capsuleView, focusRingView].filter { !$0.isHidden }
        backdrop.forEach { $0.isHidden = true }
        defer { backdrop.forEach { $0.isHidden = false } }

        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        return image
    }

    /// No menu while the name is being edited or the tab is collapsed. Otherwise the pointer's
    /// capsule stays for as long as the menu is open.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard !isEditing, !isCollapsed else { return nil }
        isHovered = true
        return menuProvider?()
    }

    // MARK: - Tooltip

    /// The tooltip covers the whole capsule, which changes size with the name.
    private func updateToolTipArea() {
        if let toolTipTag {
            removeToolTip(toolTipTag)
        }
        toolTipTag = toolTipProvider == nil || !showsToolTip ? nil : addToolTip(bounds, owner: self, userData: nil)
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        toolTipProvider?() ?? ""
    }

    // MARK: - Dropping items

    // Dropping cards on a pinboard's tab pins them there; on the history's tab, it brings them
    // to its front. The tab does not become the selected one, and hovering over it does not
    // switch to it.

    /// Every tab takes items, if somebody is listening.
    private var acceptsItems: Bool {
        onDropItems != nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDragDestination = acceptsItems
        return isDragDestination ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDragDestination = false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isDragDestination = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let ids = ItemDragType.itemIDs(in: sender.draggingPasteboard)
        guard acceptsItems, !ids.isEmpty else { return false }
        onDropItems?(ids)
        return true
    }

    // MARK: - Renaming

    /// Turns the name into an editable field with all of its text selected.
    func beginEditing() {
        guard !isEditing, let window else { return }
        isEditing = true
        isPressed = false
        label.isEditable = true
        // A name longer than the label scrolls under the insertion point while it is typed.
        label.cell?.isScrollable = true
        focusRingView.isHidden = false
        restyle()
        // Becoming first responder selects the whole name.
        if !window.makeFirstResponder(label) {
            finishEditing(typed: nil)
        }
    }

    /// Ends a rename keeping what was typed.
    func commitEditing() {
        guard isEditing else { return }
        guard let window else {
            finishEditing(typed: nil)
            return
        }
        // Taking focus away makes the field end editing, which arrives at
        // `controlTextDidEndEditing` like any other loss of focus.
        window.makeFirstResponder(nil)
    }

    /// Ends a rename discarding what was typed.
    func cancelEditing() {
        guard isEditing else { return }
        // Aborting drops the field editor without the end-of-editing notification.
        label.abortEditing()
        finishEditing(typed: nil)
        window?.makeFirstResponder(nil)
    }

    /// - Parameter typed: What the field holds when the rename is confirmed; nil when it is
    ///   cancelled. It is trimmed, and an empty name is kept: the tab then shows its default
    ///   one, "Untitled" for a pinboard.
    private func finishEditing(typed: String?) {
        guard isEditing else { return }
        isEditing = false

        let name = typed?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = name == item.name ? nil : name
        // Shown at once; the store will confirm it later with the same value.
        if let newName {
            item.name = TabBarItem.displayName(newName, kind: item.kind)
        }
        label.isEditable = false
        label.isSelectable = false
        // Making the cell scrollable replaced the truncation with clipping.
        label.cell?.isScrollable = false
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = item.name
        focusRingView.isHidden = true
        restyle()
        onEndEditing?(newName)
    }

    func controlTextDidChange(_ notification: Notification) {
        onPreferredWidthChange?()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishEditing(typed: label.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            commitEditing()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Consumed here: Escape ends the rename, it does not reach the panel and close it.
            cancelEditing()
            return true
        default:
            return false
        }
    }
}
