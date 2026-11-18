import Carbon.HIToolbox
import Foundation

/// Translates between characters and virtual key codes on the user's keyboard layout, so that a
/// synthetic ⌘V means "paste" on Dvorak, AZERTY and the like, not "whatever key sits where V is
/// on ANSI", and a recorded shortcut is shown with the letter printed on the key.
public enum KeyCodeResolver {
    /// Scans key codes 0–127 on the current ASCII-capable layout, without modifiers, and returns
    /// the first whose character matches. Returns nil when the layout has no such key.
    @MainActor
    public static func keyCode(for character: Character) -> CGKeyCode? {
        guard let target = String(character).utf16.first else { return nil }
        return withCurrentLayout { translate in
            (UInt16(0)..<128).first { translate($0) == target }
        }
    }

    /// What the key types on the current ASCII-capable layout, without modifiers. Nil for keys
    /// that type nothing (function keys, arrows) or only something invisible.
    @MainActor
    public static func character(for keyCode: CGKeyCode) -> Character? {
        let unit = withCurrentLayout { translate in translate(keyCode) }
        guard let unit, let scalar = Unicode.Scalar(unit),
              !scalar.properties.isWhitespace, scalar.properties.generalCategory != .control
        else { return nil }
        return Character(scalar)
    }

    /// Runs `body` with a function that gives the first UTF-16 unit a key code types.
    @MainActor
    private static func withCurrentLayout<Result>(_ body: ((UInt16) -> UniChar?) -> Result?) -> Result? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        return layoutData.withUnsafeBytes { buffer -> Result? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            return body { keyCode in
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout,
                    keyCode,
                    UInt16(kUCKeyActionDisplay),
                    0,
                    keyboardType,
                    0,
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
                return status == noErr && length > 0 ? characters[0] : nil
            }
        }
    }
}
