import CoreGraphics
import Foundation

/// A key press such as `cmd+shift+v`, `return` or `shift+left`, parsed from text.
public struct KeyCombo: Equatable, Sendable {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
        public static let function = Modifiers(rawValue: 1 << 4)

        /// Press order, with the virtual key code of the left-hand modifier key and its event flag.
        public static let pressOrder: [(modifier: Modifiers, keyCode: UInt16, flag: CGEventFlags)] = [
            (.control, 59, .maskControl),
            (.option, 58, .maskAlternate),
            (.shift, 56, .maskShift),
            (.command, 55, .maskCommand),
            (.function, 63, .maskSecondaryFn),
        ]

        static let names: [String: Modifiers] = [
            "cmd": .command, "command": .command, "⌘": .command,
            "shift": .shift, "⇧": .shift,
            "opt": .option, "option": .option, "alt": .option, "⌥": .option,
            "ctrl": .control, "control": .control, "⌃": .control,
            "fn": .function,
        ]
    }

    public enum Key: Equatable, Sendable {
        /// A key with a fixed virtual key code on every layout.
        case named(NamedKey)
        /// A printable character whose key code depends on the keyboard layout.
        case character(Character)
    }

    public var modifiers: Modifiers
    public var key: Key

    public init(modifiers: Modifiers, key: Key) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Parses `modifier+modifier+key`. Names are case-insensitive; `+` alone or a trailing `++` means the plus key.
    public init(parsing text: String) throws {
        var tokens = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        if text == "+" || text.hasSuffix("++") {
            tokens = Array(tokens.dropLast(2)) + ["+"]
        }
        guard let keyToken = tokens.last, !keyToken.isEmpty, !tokens.dropLast().contains("") else {
            throw ProbeError.usage("malformed key combo '\(text)'")
        }

        var modifiers: Modifiers = []
        for token in tokens.dropLast() {
            guard let modifier = Modifiers.names[token.lowercased()] else {
                throw ProbeError.usage("unknown modifier '\(token)' in '\(text)'")
            }
            modifiers.insert(modifier)
        }

        if let named = NamedKey(token: keyToken) {
            self.init(modifiers: modifiers, key: .named(named))
        } else if keyToken.count == 1, let character = keyToken.lowercased().first {
            self.init(modifiers: modifiers, key: .character(character))
        } else {
            throw ProbeError.usage("unknown key '\(keyToken)' in '\(text)'")
        }
    }

    /// Event flags carried by the key event itself: the modifiers plus what hardware adds for the key.
    public var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        for entry in Modifiers.pressOrder where modifiers.contains(entry.modifier) {
            flags.insert(entry.flag)
        }
        if case .named(let named) = key { flags.formUnion(named.implicitFlags) }
        return flags
    }
}

/// Keys addressed by name. Their virtual key codes do not depend on the keyboard layout.
public enum NamedKey: String, CaseIterable, Sendable {
    case `return`, enter, tab, space, delete, forwardDelete = "forwarddelete", escape
    case left, right, up, down, home, end, pageUp = "pageup", pageDown = "pagedown"
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    private static let aliases: [String: NamedKey] = [
        "esc": .escape, "backspace": .delete, "del": .forwardDelete, "ret": .return,
    ]

    public init?(token: String) {
        let name = token.lowercased()
        guard let key = NamedKey(rawValue: name) ?? Self.aliases[name] else { return nil }
        self = key
    }

    public var keyCode: UInt16 {
        switch self {
        case .return: 36
        case .enter: 76 // keypad Enter
        case .tab: 48
        case .space: 49
        case .delete: 51
        case .forwardDelete: 117
        case .escape: 53
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        case .home: 115
        case .end: 119
        case .pageUp: 116
        case .pageDown: 121
        case .f1: 122
        case .f2: 120
        case .f3: 99
        case .f4: 118
        case .f5: 96
        case .f6: 97
        case .f7: 98
        case .f8: 100
        case .f9: 101
        case .f10: 109
        case .f11: 103
        case .f12: 111
        }
    }

    /// Flags a physical keyboard sets for this key even when no modifier is held.
    public var implicitFlags: CGEventFlags {
        switch self {
        case .left, .right, .up, .down: [.maskSecondaryFn, .maskNumericPad]
        case .home, .end, .pageUp, .pageDown, .forwardDelete: .maskSecondaryFn
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12: .maskSecondaryFn
        case .enter: .maskNumericPad
        case .return, .tab, .space, .delete, .escape: []
        }
    }
}

extension KeyCombo.Modifiers {
    /// Parses modifiers alone, such as `cmd` or `cmd+shift`.
    public init(parsing text: String) throws {
        var modifiers: KeyCombo.Modifiers = []
        for token in text.split(separator: "+") {
            guard let modifier = Self.names[token.lowercased()] else {
                throw ProbeError.usage("unknown modifier '\(token)' in '\(text)'")
            }
            modifiers.insert(modifier)
        }
        guard !modifiers.isEmpty else { throw ProbeError.usage("name at least one modifier") }
        self = modifiers
    }
}
