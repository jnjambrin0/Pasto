import PastoInput
import PastoUI

extension KeyEquivalent {
    /// The combination as a tooltip writes it: modifier glyphs in the system's order, then the
    /// character in capitals ("⇧⌘N").
    var displayString: String {
        ShortcutDisplay.modifierGlyphs(modifiers) + character.uppercased()
    }
}
