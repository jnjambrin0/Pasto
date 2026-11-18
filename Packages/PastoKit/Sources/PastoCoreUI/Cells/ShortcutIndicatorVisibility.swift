import AppKit

/// Which parts of a card's shortcut indicator show for a given keyboard state. There is no
/// disabled look: a part is shown or it is not.
nonisolated struct ShortcutIndicatorVisibility: Sendable, Equatable {
    /// The glyph announcing that a paste would be plain text.
    var showsPlainTextGlyph: Bool
    /// The card's quick paste number.
    var showsNumber: Bool

    var isVisible: Bool { showsPlainTextGlyph || showsNumber }

    /// Nothing shows: the state of an indicator that has no settings yet.
    static let hidden = ShortcutIndicatorVisibility(
        isEnabled: false, heldFlags: [], plainTextFlags: [], quickPasteFlags: [], quickPasteIndex: nil
    )

    /// - Parameters:
    ///   - isEnabled: the strip has keyboard focus.
    ///   - heldFlags: the modifier keys down right now.
    ///   - quickPasteIndex: the card's number, if it is one of the first nine.
    init(
        isEnabled: Bool,
        heldFlags: NSEvent.ModifierFlags,
        plainTextFlags: NSEvent.ModifierFlags,
        quickPasteFlags: NSEvent.ModifierFlags,
        quickPasteIndex: Int?
    ) {
        // An empty modifier set is contained in any state, so a user who clears the plain-text
        // modifier sees the glyph all the time.
        showsPlainTextGlyph = isEnabled && heldFlags.isSuperset(of: plainTextFlags)
        showsNumber = isEnabled && heldFlags.isSuperset(of: quickPasteFlags) && quickPasteIndex != nil
    }
}
