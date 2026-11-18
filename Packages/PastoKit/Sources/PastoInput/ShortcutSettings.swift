import AppKit
import Carbon.HIToolbox
import PastoFoundation

// The shortcuts the user records in Settings › Shortcuts. Each is JSON data holding `keyCode` and
// `internalModifiers`; nothing stored means "no shortcut", which turns the function off.

/// A shortcut setting. Write it with `ConfigStore.setShortcut(_:for:)`.
public typealias ShortcutKey = ConfigKey<JSONConfigValue<Shortcut?>>

extension ConfigKey where Value == JSONConfigValue<Shortcut?> {
    /// Opens and closes the panel, system-wide.
    public static var activationShortcut: ShortcutKey { ConfigKey("activationShortcut", default: JSONConfigValue(nil)) }

    /// Opens the Paste Stack, system-wide.
    public static var pasteStackShortcut: ShortcutKey { ConfigKey("pasteStackShortcut", default: JSONConfigValue(nil)) }

    /// Inside the panel: the tab after the selected one.
    public static var nextPinboardShortcut: ShortcutKey { ConfigKey("nextPinboardShortcut", default: JSONConfigValue(nil)) }

    /// Inside the panel: the tab before the selected one.
    public static var previousPinboardShortcut: ShortcutKey {
        ConfigKey("previousPinboardShortcut", default: JSONConfigValue(nil))
    }
}

extension ConfigKey where Value == Bool {
    /// Whether the shortcuts received their initial values. Afterwards an empty shortcut is the
    /// user's choice and is left empty.
    public static var isInitialShortcutsMigrationCompleted: ConfigKey<Bool> {
        ConfigKey("isInitialShortcutsMigrationCompleted", default: false)
    }
}

extension ConfigStore {
    public func shortcut(for key: ShortcutKey) -> Shortcut? {
        value(for: key).value
    }

    /// Clearing a shortcut forgets the key instead of storing an empty value.
    public func setShortcut(_ shortcut: Shortcut?, for key: ShortcutKey) {
        if let shortcut {
            set(JSONConfigValue(shortcut), for: key)
        } else {
            reset(key)
        }
    }
}

/// The values the shortcut settings start with, and go back to with "Reset Shortcuts to Default".
public enum ShortcutDefaults {
    public static let activation = Shortcut(keyCode: kVK_ANSI_V, modifiers: [.command, .shift])
    public static let pasteStack = Shortcut(keyCode: kVK_ANSI_C, modifiers: [.command, .shift])
    public static let nextPinboard = Shortcut(keyCode: kVK_RightArrow, modifiers: .command)
    public static let previousPinboard = Shortcut(keyCode: kVK_LeftArrow, modifiers: .command)

    /// What a new installation takes instead of `activation` when something else on the Mac
    /// already answers to it.
    public static let alternateActivation = Shortcut(keyCode: kVK_ANSI_V, modifiers: [.command, .shift, .control])
    /// What a new installation takes instead of `pasteStack` when something else has it.
    public static let alternatePasteStack = Shortcut(keyCode: kVK_ANSI_C, modifiers: [.command, .shift, .control])

    private static let shortcuts: [(key: ShortcutKey, shortcut: Shortcut)] = [
        (.activationShortcut, activation),
        (.pasteStackShortcut, pasteStack),
        (.nextPinboardShortcut, nextPinboard),
        (.previousPinboardShortcut, previousPinboard),
    ]

    /// The shortcuts each setting tries on a new installation, in order. Only the system-wide
    /// ones can clash with another app; the two inside the panel are always free.
    private static let initialChoices: [(key: ShortcutKey, choices: [Shortcut], isSystemWide: Bool)] = [
        (.activationShortcut, [activation, alternateActivation], true),
        (.pasteStackShortcut, [pasteStack, alternatePasteStack], true),
        (.nextPinboardShortcut, [nextPinboard], false),
        (.previousPinboardShortcut, [previousPinboard], false),
    ]

    /// Run once per installation, at launch and before onboarding: gives every shortcut that
    /// has no value its initial one. The defaults of the keys themselves are empty, so that
    /// clearing a shortcut sticks. A stored value that cannot be read counts as no value.
    ///
    /// The activation and Paste Stack shortcuts take their first choice that `isAvailable`
    /// accepts — ⇧⌘V, else ⌃⇧⌘V; ⇧⌘C, else ⌃⇧⌘C — and stay empty when neither is. The
    /// shortcuts inside the panel are always given their value.
    ///
    /// - Parameter isAvailable: Whether nothing else on the Mac answers to a combination now:
    ///   macOS, a hot key held by another app or a clipboard manager known to use it.
    public static func applyInitialShortcuts(to config: ConfigStore, isAvailable: (Shortcut) -> Bool) {
        guard !config.value(for: .isInitialShortcutsMigrationCompleted) else { return }
        for (key, choices, isSystemWide) in initialChoices where config.shortcut(for: key) == nil {
            config.setShortcut(isSystemWide ? choices.first(where: isAvailable) : choices.first, for: key)
        }
        config.set(true, for: .isInitialShortcutsMigrationCompleted)
    }

    /// The system-wide shortcuts the user has, in the order Settings lists them, that something
    /// else on the Mac answers to now: Pasto's hot key would not fire, or not only Pasto's.
    /// Asked at launch, before Pasto holds them itself.
    ///
    /// - Parameter isAvailable: As for `applyInitialShortcuts(to:isAvailable:)`.
    public static func takenShortcuts(in config: ConfigStore, isAvailable: (Shortcut) -> Bool) -> [ShortcutKey] {
        initialChoices
            .filter(\.isSystemWide)
            .map(\.key)
            .filter { key in config.shortcut(for: key).map { !isAvailable($0) } ?? false }
    }

    /// The four shortcuts and the two modifiers, as they were on a new installation.
    public static func restore(in config: ConfigStore) {
        for (key, shortcut) in shortcuts {
            config.setShortcut(shortcut, for: key)
        }
        config.set(ConfigKey.quickPasteModifierFlags.defaultValue, for: .quickPasteModifierFlags)
        config.set(ConfigKey.plainTextModifierFlags.defaultValue, for: .plainTextModifierFlags)
    }
}
