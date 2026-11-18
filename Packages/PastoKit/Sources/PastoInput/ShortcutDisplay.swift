import AppKit
import Carbon.HIToolbox

/// How a shortcut is written for the user: modifier glyphs in the system's order, then the key.
public enum ShortcutDisplay {
    /// ⌃⌥⇧⌘, the order menus use.
    public static func modifierGlyphs(_ modifiers: NSEvent.ModifierFlags) -> String {
        var glyphs = ""
        if modifiers.contains(.control) { glyphs += "⌃" }
        if modifiers.contains(.option) { glyphs += "⌥" }
        if modifiers.contains(.shift) { glyphs += "⇧" }
        if modifiers.contains(.command) { glyphs += "⌘" }
        return glyphs
    }

    /// The space bar where there is no room for its name, as in a help tag.
    public static let spaceKeyGlyph = "␣"

    /// - Parameters:
    ///   - spaceKeyName: The space bar's name, in the language of whoever shows it.
    ///   - layoutCharacter: What a key code types on the keyboard layout in use; asked only for
    ///     keys that have no fixed name.
    public static func string(for shortcut: Shortcut, spaceKeyName: String, layoutCharacter: (Int) -> Character?) -> String {
        modifierGlyphs(shortcut.modifiers) + keyName(for: shortcut.keyCode, spaceKeyName: spaceKeyName, layoutCharacter: layoutCharacter)
    }

    /// The shortcut as the active keyboard layout labels it. A recorder field names the space
    /// bar in words; elsewhere it can stay a glyph.
    @MainActor
    public static func string(for shortcut: Shortcut, spaceKeyName: String = spaceKeyGlyph) -> String {
        string(for: shortcut, spaceKeyName: spaceKeyName) { keyCode in
            CGKeyCode(exactly: keyCode).flatMap(KeyCodeResolver.character(for:))
        }
    }

    /// What a recorder field shows: the shortcut, a placeholder when there is none and, while
    /// it records, the modifiers held so far.
    @MainActor
    public static func recorderText(
        for shortcut: Shortcut?,
        recorder: ShortcutRecorder?,
        recordingPlaceholder: String,
        emptyPlaceholder: String,
        spaceKeyName: String
    ) -> String {
        if let recorder, recorder.isRecording {
            return recorder.heldModifiers.isEmpty ? recordingPlaceholder : modifierGlyphs(recorder.heldModifiers)
        }
        return shortcut.map { string(for: $0, spaceKeyName: spaceKeyName) } ?? emptyPlaceholder
    }

    static func keyName(for keyCode: Int, spaceKeyName: String, layoutCharacter: (Int) -> Character?) -> String {
        if keyCode == kVK_Space { return spaceKeyName }
        if let name = fixedKeyNames[keyCode] { return name }
        if let character = layoutCharacter(keyCode) { return String(character).uppercased() }
        // A key the layout cannot name still has to show as something the user can tell apart.
        return "#\(keyCode)"
    }

    /// Keys that mean the same on every layout: their names never come from the layout.
    private static let fixedKeyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Escape: "⎋",
            kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←",
            kVK_RightArrow: "→",
            kVK_UpArrow: "↑",
            kVK_DownArrow: "↓",
            kVK_Help: "?⃝",
            kVK_PageUp: "⇞",
            kVK_PageDown: "⇟",
            kVK_Tab: "⇥",
            kVK_Return: "↩",
            kVK_ANSI_KeypadClear: "⌧",
            kVK_ANSI_KeypadEnter: "⌅",
            kVK_End: "↘",
            kVK_Home: "↖",
            // The numeric keypad, by what is printed on each key.
            kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2", kVK_ANSI_Keypad3: "3",
            kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5", kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7",
            kVK_ANSI_Keypad8: "8", kVK_ANSI_Keypad9: "9", kVK_ANSI_KeypadDecimal: ".",
            kVK_ANSI_KeypadMultiply: "*", kVK_ANSI_KeypadPlus: "+", kVK_ANSI_KeypadMinus: "-",
            kVK_ANSI_KeypadDivide: "/", kVK_ANSI_KeypadEquals: "=",
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, keyCode) in functionKeys.enumerated() {
            names[keyCode] = "F\(index + 1)"
        }
        return names
    }()
}
