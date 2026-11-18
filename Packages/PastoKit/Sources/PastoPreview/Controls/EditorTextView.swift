import AppKit

/// The text view inside `TextEditor`: it keeps what is pasted down to the editor's formatting,
/// leaves its own colouring out of what is copied, and toggles the four traits.
final class EditorTextView: NSTextView {
    /// Whether the text's colours are the content's own. When they are not — the editor put
    /// them there to suit its background — a copy leaves without them.
    var copiesTextColors = false

    private static let layoutOrientationAction = #selector(NSTextView.changeLayoutOrientation(_:))

    // MARK: - Menus

    /// Vertical text is not something an item can hold.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        item.action != Self.layoutOrientationAction && super.validateUserInterfaceItem(item)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        let action = Self.layoutOrientationAction
        for item in menu.items where item.action == action || item.submenu?.items.contains(where: { $0.action == action }) == true {
            menu.removeItem(item)
        }
        return menu
    }

    // MARK: - Pasteboard

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard !copiesTextColors, range.length > 0, let textStorage else {
            super.copy(sender)
            return
        }
        let selection = NSMutableAttributedString(attributedString: textStorage.attributedSubstring(from: range))
        selection.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: selection.length))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([selection])
    }

    override func paste(_ sender: Any?) {
        let pasted = NSPasteboard.general.readObjects(forClasses: [NSAttributedString.self])?.first as? NSAttributedString
        guard let pasted, let textStorage else {
            super.paste(sender)
            return
        }
        let text = NSMutableAttributedString(attributedString: EditableText.normalized(pasted))
        if let color = typingAttributes[.foregroundColor] {
            text.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.length))
        }
        // Asking and telling the text view around the change is what makes it undoable.
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: text.string) else { return }
        textStorage.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    // MARK: - Traits

    /// The traits of the selection's first character, or of what would be typed next.
    var activeTraits: Set<TextTrait> {
        let range = selectedRange()
        let attributes = if range.length > 0, let textStorage {
            textStorage.attributes(at: range.location, effectiveRange: nil)
        } else {
            typingAttributes
        }
        return Set(TextTrait.allCases.filter { $0.isActive(in: attributes) })
    }

    /// Turns a trait on or off for the whole selection — the opposite of what its first
    /// character has — or, without a selection, for what is typed next.
    func toggle(_ trait: TextTrait) {
        guard isEditable else { return }
        let isOn = !activeTraits.contains(trait)
        let range = selectedRange()

        guard range.length > 0, let textStorage else {
            var attributes = typingAttributes
            trait.set(isOn, in: &attributes)
            typingAttributes = attributes
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        textStorage.beginEditing()
        textStorage.enumerateAttributes(in: range) { attributes, runRange, _ in
            var attributes = attributes
            trait.set(isOn, in: &attributes)
            textStorage.setAttributes(attributes, range: runRange)
        }
        textStorage.endEditing()
        didChangeText()
    }
}
