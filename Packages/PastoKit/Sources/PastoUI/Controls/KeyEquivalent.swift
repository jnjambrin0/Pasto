import AppKit

/// A key combination a control answers to while its window is key.
///
/// It is matched by the character the key produces, not by key code, so it follows the keyboard
/// layout the way menu key equivalents do.
public nonisolated struct KeyEquivalent: Sendable, Equatable {
    /// The modifiers that take part in a match; Caps Lock and the arrow keys' own flags do not.
    private static let significantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    public let character: String
    public let modifiers: NSEvent.ModifierFlags

    public init(_ character: String, modifiers: NSEvent.ModifierFlags) {
        self.character = character.lowercased()
        self.modifiers = modifiers.intersection(Self.significantModifiers)
    }

    public func matches(_ event: NSEvent) -> Bool {
        // Only key events carry characters; asking any other event for them raises.
        event.type == .keyDown
            && matches(characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
    }

    /// Shift changes the character a key produces ("n" becomes "N"), hence the case-insensitive
    /// comparison: Shift is matched through the modifiers instead.
    func matches(characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        characters?.lowercased() == character
            && modifiers.intersection(Self.significantModifiers) == self.modifiers
    }
}
