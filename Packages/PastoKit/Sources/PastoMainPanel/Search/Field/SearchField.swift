import AppKit
import PastoUI

/// The search field: a capsule with a magnifying glass, a single line of text in which filters
/// are tokens, a button that clears it and another that opens the filter browser.
///
/// It shows what it is told and reports what the user does; what an edit means is decided by
/// whoever handles `onTextShouldChange`.
final class SearchField: LayerBackedView, NSTextViewDelegate {
    private static let undoKeyEquivalent = KeyEquivalent("z", modifiers: .command)
    private static let redoKeyEquivalent = KeyEquivalent("z", modifiers: [.command, .shift])
    private static let bounceAnimationKey = "filtersBounce"

    let textView = SearchTextView.make()

    /// The user is about to change the content into the first argument, leaving the cursor at
    /// the second. Returning false cancels the edit.
    var onTextShouldChange: ((NSAttributedString, NSRange) -> Bool)?
    var onSelectionChange: ((NSRange) -> Void)?
    /// The filters button was clicked.
    var onShowFilters: (() -> Void)?
    /// Return.
    var onEnter: (() -> Void)?
    /// Escape.
    var onCancel: (() -> Void)?
    /// The clear button was clicked.
    var onClear: (() -> Void)?
    /// The keyboard focus left the field: its text and its buttons.
    var onEndEditing: (() -> Void)?
    /// ⌘Z and ⇧⌘Z; each returns whether it did anything.
    var onUndo: (() -> Bool)?
    var onRedo: (() -> Bool)?

    private let iconView = SymbolView(symbol: SearchMetrics.Field.icon)
    private let scrollView = SearchTextScrollView(frame: .zero)
    private let clearButton = SearchFieldButton(symbol: SearchMetrics.Field.clearSymbol, label: SearchStrings.clear)
    let filtersButton = SearchFieldButton(symbol: SearchMetrics.Field.filtersSymbol, label: SearchStrings.filters)

    /// False while the search is not active and the field is out of sight: neither its text nor
    /// its buttons take the keyboard focus then, and assistive technologies do not see them.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            textView.canAcceptFocus = isActive
            textView.setAccessibilityElement(isActive)
            for button in buttons {
                button.isReachable = isActive
            }
            if !isActive, let window, buttons.contains(where: { $0 === window.firstResponder }) {
                window.makeFirstResponder(nil)
            }
        }
    }

    private var buttons: [SearchFieldButton] { [clearButton, filtersButton] }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        // Untinted: AppKit draws the template in its default grey.
        addSubview(iconView)

        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.focusRingType = .exterior
        scrollView.documentView = textView
        // The text is the search field to VoiceOver, not something inside a scroll area.
        scrollView.setAccessibilityElement(false)
        addSubview(scrollView)

        textView.delegate = self
        textView.setAccessibilityElement(false)

        clearButton.target = self
        clearButton.action = #selector(clear)
        clearButton.isEnabled = false
        clearButton.isHidden = true
        clearButton.alphaValue = 0
        addSubview(clearButton)

        filtersButton.target = self
        filtersButton.action = #selector(showFilters)
        filtersButton.wantsLayer = true
        filtersButton.toolTip = "\(SearchStrings.filters) (⌘F)"
        addSubview(filtersButton)

        for button in buttons {
            button.onResignFocus = { [weak self] in self?.focusDidLeavePart() }
        }
    }

    // MARK: - Content

    /// Replaces the content and the selection, scrolling the selection into view.
    func show(_ text: NSAttributedString, selection: NSRange) {
        guard let storage = textView.textStorage else { return }
        // One transaction, so that the layout hears of the whole replacement at once and never
        // lays out a text that is half gone.
        if let content = textView.textContentStorage {
            content.performEditingTransaction { storage.setAttributedString(text) }
        } else {
            storage.setAttributedString(text)
        }
        contentDidChange()
        textView.setSelectedRange(selection)
        textView.scrollRangeToVisible(selection)
    }

    /// Selects the token whose attachment has this identifier.
    func selectToken(_ id: UUID) {
        guard let storage = textView.textStorage else { return }
        window?.makeFirstResponder(textView)
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard (value as? SearchFilterAttachment)?.id == id else { return }
            textView.setSelectedRange(range)
            stop.pointee = true
        }
    }

    /// Where the characters of `range` are drawn, in the field's coordinates; nil when the text
    /// has not been laid out.
    func rect(forCharacterRange range: NSRange) -> NSRect? {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return nil }

        layoutManager.textViewportLayoutController.layoutViewport()
        var rect: NSRect?
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            rect = rect?.union(frame) ?? frame
            return true
        }
        guard let rect else { return nil }
        let origin = textView.textContainerOrigin
        return convert(rect.offsetBy(dx: origin.x, dy: origin.y), from: textView)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let metrics = SearchMetrics.Field.self
        layer?.cornerRadius = bounds.height / 2

        let iconSize = iconView.imageSize
        iconView.frame = NSRect(
            x: metrics.iconLeadingInset,
            y: (bounds.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        filtersButton.frame = NSRect(
            x: bounds.maxX - metrics.filtersTrailingInset - metrics.filtersButtonWidth,
            y: 0,
            width: metrics.filtersButtonWidth,
            height: bounds.height
        )

        // The input area: the text, and the clear button at its trailing end.
        let inputMinX = iconView.frame.maxX + metrics.iconToInputSpacing
        let inputMaxX = filtersButton.frame.minX - metrics.inputToFiltersSpacing
        let inputY = (bounds.height - metrics.inputHeight) / 2
        clearButton.frame = NSRect(
            x: inputMaxX - metrics.clearButtonSide,
            y: (bounds.height - metrics.clearButtonSide) / 2,
            width: metrics.clearButtonSide,
            height: metrics.clearButtonSide
        )
        scrollView.frame = NSRect(
            x: inputMinX,
            y: inputY,
            width: max(clearButton.frame.minX - metrics.textToClearSpacing - inputMinX, 0),
            height: metrics.inputHeight
        )
        // The text fills the visible area even when it is short, so a click anywhere in it
        // places the insertion point.
        textView.minSize = scrollView.contentSize
        if textView.frame.width < scrollView.contentSize.width || textView.frame.height != scrollView.contentSize.height {
            textView.setFrameSize(NSSize(
                width: max(textView.frame.width, scrollView.contentSize.width),
                height: scrollView.contentSize.height
            ))
        }
        scrollView.focusRingBounds = scrollView.convert(bounds, from: self)
    }

    override func updateLayerColors() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(SearchMetrics.Field.fillOpacity).cgColor
    }

    // MARK: - Mouse and keys

    /// A click anywhere on the capsule that no control takes goes to the text.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textView)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === textView else { return super.performKeyEquivalent(with: event) }
        if Self.undoKeyEquivalent.matches(event) { return onUndo?() ?? false }
        if Self.redoKeyEquivalent.matches(event) { return onRedo?() ?? false }
        return super.performKeyEquivalent(with: event)
    }

    /// Whether the keyboard focus is in the field: in its text or, with Full Keyboard Access,
    /// on one of its buttons.
    var containsKeyboardFocus: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder === textView || buttons.contains { $0 === responder }
    }

    /// Keys a focused button does not take for itself, with Full Keyboard Access on: Escape is
    /// the field's, as in the text, Tab moves on, and anything else goes to the text.
    override func keyDown(with event: NSEvent) {
        guard let window, buttons.contains(where: { $0 === window.firstResponder }), event.keyCode != KeyCode.tab else {
            return super.keyDown(with: event)
        }
        if event.keyCode == KeyCode.escape {
            onCancel?()
            return
        }
        window.makeFirstResponder(textView)
        textView.keyDown(with: event)
    }

    /// The focus left the text or a button. Without Full Keyboard Access only the text ever has
    /// it, and leaving it is leaving the field. With it, the focus may only be moving between
    /// the text and the buttons, which is known once it has moved.
    private func focusDidLeavePart() {
        guard NSApp.isFullKeyboardAccessEnabled else {
            onEndEditing?()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !containsKeyboardFocus else { return }
            onEndEditing?()
        }
    }

    @objc private func clear() {
        window?.makeFirstResponder(textView)
        onClear?()
    }

    @objc private func showFilters() {
        onShowFilters?()
    }

    /// A quick swell of the filters button, which marks the filter browser opening and closing.
    func bounceFiltersButton() {
        guard let layer = filtersButton.layer else { return }
        let center = CGPoint(x: filtersButton.bounds.midX, y: filtersButton.bounds.midY)
        let bounce = CAKeyframeAnimation(keyPath: "transform")
        // A view's layer is anchored at its origin, so the scale is applied around the centre.
        bounce.values = SearchMetrics.Field.bounceScales.map { scale in
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(transform, -center.x, -center.y, 0))
        }
        bounce.keyTimes = SearchMetrics.Field.bounceKeyTimes
        bounce.calculationMode = .cubic
        bounce.duration = SearchMetrics.Field.bounceDuration
        layer.add(bounce, forKey: Self.bounceAnimationKey)
    }

    // MARK: - Clear button

    /// The clear button shows while there is anything to clear; a token counts.
    private func updateClearButton() {
        let hasText = !textView.string.isEmpty
        guard hasText != clearButton.isEnabled else { return }
        clearButton.isEnabled = hasText
        if hasText {
            clearButton.isHidden = false
        } else if window?.firstResponder === clearButton {
            // Escape cleared the field from the button, which is going away: the focus goes to
            // the text, once the text storage is done with the edit.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window, window.firstResponder === clearButton, !clearButton.isEnabled else { return }
                window.makeFirstResponder(textView)
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SearchMetrics.Field.clearFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clearButton.animator().alphaValue = hasText ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.textView.string.isEmpty else { return }
                self.clearButton.isHidden = true
            }
        }
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard let storage = textView.textStorage else { return false }
        // Nil means only attributes change, which is none of the query's business.
        guard let replacement = replacementString else { return true }

        // The field has one line: pasted line breaks become spaces.
        let singleLine = SearchFieldText.singleLine(replacement)
        if singleLine != replacement {
            textView.insertText(singleLine, replacementRange: range)
            return false
        }

        // Deleting next to a token selects it first; deleting again removes it.
        if replacement.isEmpty, range.length == 1, textView.selectedRange() != range,
           storage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil {
            textView.setSelectedRange(range)
            return false
        }

        let proposed = NSMutableAttributedString(attributedString: storage)
        proposed.replaceCharacters(in: range, with: replacement)
        let selection = NSRange(location: range.location + replacement.utf16.count, length: 0)
        return onTextShouldChange?(proposed, selection) ?? true
    }

    /// Only Return and Escape are the field's own. The rest is the field editor's: Tab ends
    /// editing and the key view loop takes the focus to the strip, and ↑ and ↓ move the insertion
    /// point to the start and the end of the line. The suggestions menu, while shown, takes the
    /// arrows before they get here.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onEnter?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        default:
            return false
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        textView.applyTextAttributes()
        onSelectionChange?(textView.selectedRange())
    }

    func textDidEndEditing(_ notification: Notification) {
        focusDidLeavePart()
    }

    func textDidChange(_ notification: Notification) {
        contentDidChange()
    }

    /// Brings the field's own parts up to date with the text: after the user's edit is complete
    /// (`textDidChange`) or after `show`. Never from inside the text storage's editing: changing
    /// the text container there makes the layout run against a text it has only half heard about,
    /// which leaves the old text on screen and, at the next layout, raises a range exception.
    private func contentDidChange() {
        updateClearButton()
        textView.applyTextAttributes()
        // A token is as tall as the input area; plain text is centred in it by an inset.
        let hasTokens = textView.textStorage?.containsAttachments ?? false
        let inset = NSSize(width: 0, height: hasTokens ? 0 : SearchMetrics.Field.textVerticalInset)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
        }
    }
}
