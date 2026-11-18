import AppKit
import PastoFoundation

// Modifier keys the user can change in Settings › Shortcuts, stored as the raw bits of
// `NSEvent.ModifierFlags`.

extension ConfigKey where Value == Int {
    /// Held with a digit 1–9 to paste the item in that position. ⌘ by default.
    public static var quickPasteModifierFlags: ConfigKey<Int> {
        ConfigKey("quickPasteModifierFlags", default: Int(NSEvent.ModifierFlags.command.rawValue))
    }

    /// Held while pasting or copying to get plain text. ⇧ by default.
    public static var plainTextModifierFlags: ConfigKey<Int> {
        ConfigKey("plainTextModifierFlags", default: Int(NSEvent.ModifierFlags.shift.rawValue))
    }
}
