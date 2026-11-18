import AppKit
import Carbon.HIToolbox

/// What a key press means while a shortcut is being recorded.
public enum ShortcutRecording: Equatable, Sendable {
    case record(Shortcut)
    /// Leave the field without a shortcut, which turns its function off.
    case clear
    /// Stop recording and keep what the field had.
    case cancel
    /// ⌘W, ⌘Q, Tab or ⇧Tab: stop recording, keep what the field had, and let the key close the
    /// window, quit or move the focus as it always does.
    case cancelAndPassOn
    /// Not usable as a shortcut: keep listening, and let the key go on to whoever wants it.
    case reject
    /// Already in use: stop recording, keep what the field had, and tell the user.
    case conflict(ShortcutConflict)

    /// The keys that are a shortcut on their own, with no modifier at all.
    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// The modifiers that make a key a shortcut. Shift alone does not: it is how letters are typed.
    private static let shortcutModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

    private static let windowAndApplicationKeys: Set<Int> = [kVK_ANSI_W, kVK_ANSI_Q]

    /// - Parameters:
    ///   - otherShortcuts: Pasto's other shortcuts, which cannot be had twice.
    ///   - validate: Asked last, for a combination that is fine as far as Pasto goes: what else
    ///     on the Mac answers to it.
    public static func outcome(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags,
        otherShortcuts: [NamedShortcut],
        validate: (Shortcut) -> ShortcutConflict?
    ) -> ShortcutRecording {
        let shortcut = Shortcut(keyCode: keyCode, modifiers: modifiers)
        if shortcut.modifiers.isEmpty {
            switch keyCode {
            case kVK_Delete, kVK_ForwardDelete: return .clear
            case kVK_Escape: return .cancel
            default: break
            }
        }
        if shortcut.modifiers == .command, windowAndApplicationKeys.contains(keyCode) {
            return .cancelAndPassOn
        }
        // Moving the focus away with the keyboard leaves nothing recording behind.
        if keyCode == kVK_Tab, shortcut.modifiers.isSubset(of: .shift) {
            return .cancelAndPassOn
        }
        guard functionKeys.contains(keyCode) || !shortcut.modifiers.isDisjoint(with: shortcutModifiers) else {
            return .reject
        }
        if let other = otherShortcuts.first(where: { $0.shortcut == shortcut }) {
            return .conflict(.usedByShortcut(other.name))
        }
        if let conflict = validate(shortcut) {
            return .conflict(conflict)
        }
        return .record(shortcut)
    }
}
