/// Why a key combination cannot become a shortcut. Recording stops, the field keeps what it had
/// and the user is told.
public enum ShortcutConflict: Equatable, Sendable {
    /// Another of Pasto's shortcuts already has it; with that shortcut's name.
    case usedByShortcut(String)
    /// macOS has it, among the keyboard shortcuts turned on in System Settings.
    case usedBySystem
    /// An item of Pasto's menu bar has it as its key equivalent; with the item's title.
    case usedByMenuItem(String)
}
