import CoreGraphics
import os
import PastoFoundation

/// Posts ⌘-letter shortcuts to the frontmost application. Requires Accessibility permission.
///
/// The events come from a private event source: key down and key up carrying only the Command
/// flag, posted back to back at the annotated session tap.
public enum SyntheticKeystroke {
    /// Sends ⌘V. Returns false when the keyboard layout has no "v" key or the events could not be created.
    @MainActor
    @discardableResult
    public static func postPaste() -> Bool {
        postCommand("v")
    }

    /// Sends ⌘C, which is how the Paste Stack takes the selection of the frontmost application.
    /// Returns false when the keyboard layout has no "c" key or the events could not be created.
    @MainActor
    @discardableResult
    public static func postCopy() -> Bool {
        postCommand("c")
    }

    @MainActor
    private static func postCommand(_ character: Character) -> Bool {
        guard let keyCode = KeyCodeResolver.keyCode(for: character) else {
            Log.logger(.paste).error("No key produces \(String(character), privacy: .public) on the current layout")
            return false
        }
        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
