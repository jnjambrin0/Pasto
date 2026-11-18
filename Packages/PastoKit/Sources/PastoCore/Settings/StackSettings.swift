import PastoFoundation

// The Paste Stack's settings and their `UserDefaults` keys.

/// The end of the stack that new copies join. ⌘V always pastes the top row, so `top` makes the
/// stack last in, first out and `bottom` first in, first out.
public enum StackDirection: String, ConfigValue, CaseIterable {
    case top
    case bottom

    public var reversed: StackDirection {
        switch self {
        case .top: .bottom
        case .bottom: .top
        }
    }
}

extension ConfigKey where Value == StackDirection {
    public static var pasteStackDirection: ConfigKey<StackDirection> {
        ConfigKey("pasteStackDirection", default: .top)
    }
}

extension ConfigKey where Value == Bool {
    /// The stack's own "Paste as Plain Text" switch, which stays on until it is turned off.
    public static var isPasteStackPlainTextEnabled: ConfigKey<Bool> {
        ConfigKey("isPasteStackPlainTextEnabled", default: false)
    }
}

extension ConfigKey where Value == Double {
    /// The tallest the stack's panel may grow, header included, in points. Zero stands for "never
    /// resized": the limit then follows the screen the panel is on.
    public static var pasteStackHeightLimit: ConfigKey<Double> {
        ConfigKey("pasteStackHeightLimit", default: 0)
    }
}
