import AppKit
import PastoFoundation
import PastoInput

/// A single modifier key the user can assign to quick paste or to plain text mode. The setting
/// holds its `NSEvent.ModifierFlags` bits.
enum ModifierChoice: CaseIterable, Identifiable {
    case command
    case shift
    case control
    case option

    /// Shift is not offered for quick paste, where it would turn the digits into symbols.
    static let quickPasteOptions: [ModifierChoice] = [.command, .control, .option]
    static let plainTextOptions: [ModifierChoice] = [.command, .shift, .control, .option]

    var id: Self { self }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .shift: .shift
        case .control: .control
        case .option: .option
        }
    }

    var storedFlags: Int { Int(flags.rawValue) }

    /// "⌘ Command".
    var title: String {
        let name = switch self {
        case .command: SettingsStrings.commandKey
        case .shift: SettingsStrings.shiftKey
        case .control: SettingsStrings.controlKey
        case .option: SettingsStrings.optionKey
        }
        return "\(ShortcutDisplay.modifierGlyphs(flags)) \(name)"
    }

    /// The option a stored value selects. A value that is none of `options` (several keys at
    /// once, or one not offered here) reads as the setting's default.
    static func selection(forStoredFlags storedFlags: Int, among options: [ModifierChoice], default defaultFlags: Int) -> ModifierChoice {
        options.first { $0.storedFlags == storedFlags }
            ?? options.first { $0.storedFlags == defaultFlags }
            ?? .command
    }
}
