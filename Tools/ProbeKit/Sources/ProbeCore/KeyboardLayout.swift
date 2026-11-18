import Carbon.HIToolbox
import Foundation

/// Maps printable characters to virtual key codes for the current ASCII-capable keyboard layout.
@MainActor
public enum KeyboardLayout {
    /// The key that types `character` with no modifier held, or nil if the layout has no such key.
    public static func keyCode(for character: Character) -> UInt16? {
        unmodifiedKeyCodes()[character]
    }

    private static func unmodifiedKeyCodes() -> [Character: UInt16] {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        var table: [Character: UInt16] = [:]
        layoutData.withUnsafeBytes { bytes in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            // Ascending order keeps the main-row key when the keypad produces the same character.
            for keyCode in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
                )
                guard status == noErr, length == 1,
                      let character = String(utf16CodeUnits: characters, count: length).first,
                      table[character] == nil
                else { continue }
                table[character] = keyCode
            }
        }
        return table
    }
}
