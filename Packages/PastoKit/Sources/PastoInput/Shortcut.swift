import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a virtual key code plus Cocoa modifier flags. It is stored in settings
/// as JSON with these two keys.
public struct Shortcut: Hashable, Sendable, Codable {
    /// The modifiers a shortcut keeps. Caps Lock, Help and the device-dependent bits are dropped:
    /// a hot key can use none of them.
    static let significantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    public var keyCode: Int
    /// The bits of `NSEvent.ModifierFlags`; converted to Carbon masks only when registering.
    public var internalModifiers: UInt

    /// What a key code can be: the system hands them out as `CGKeyCode`.
    static let validKeyCodes = 0...Int(UInt16.max)

    public init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        internalModifiers = modifiers.intersection(Self.significantModifiers).rawValue
    }

    /// A stored shortcut whose key code no key can have is damaged: it fails to decode, and the
    /// setting reads as no shortcut instead of reaching the hot key registration.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try container.decode(Int.self, forKey: .keyCode)
        guard Self.validKeyCodes.contains(keyCode) else {
            throw DecodingError.dataCorruptedError(
                forKey: .keyCode, in: container, debugDescription: "Key code out of range: \(keyCode)"
            )
        }
        self.keyCode = keyCode
        internalModifiers = try container.decode(UInt.self, forKey: .internalModifiers)
    }

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: internalModifiers)
    }

    /// Carbon's modifier mask for `RegisterEventHotKey`. Only ⌘, ⌥, ⌃ and ⇧ take part.
    var carbonModifiers: UInt32 {
        var mask = 0
        if modifiers.contains(.command) { mask |= cmdKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        return UInt32(mask)
    }
}
