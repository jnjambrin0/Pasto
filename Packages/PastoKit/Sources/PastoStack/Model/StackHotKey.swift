import AppKit
import Carbon.HIToolbox
import PastoInput

/// The two system-wide hot keys the stack holds while it has rows. They are fixed: no setting
/// changes them.
enum StackHotKey: CaseIterable {
    case pasteNext
    case pasteAll

    var shortcut: Shortcut {
        switch self {
        case .pasteNext: Shortcut(keyCode: kVK_ANSI_V, modifiers: .command)
        case .pasteAll: Shortcut(keyCode: kVK_ANSI_V, modifiers: [.control, .option, .command])
        }
    }

    /// The name the hot key is registered under.
    var caller: String {
        switch self {
        case .pasteNext: "pasteStackPasteShortcut"
        case .pasteAll: "pasteStackPasteAllShortcut"
        }
    }
}

/// What the stack needs from the hot key center.
protocol StackHotKeyRegistering: AnyObject {
    func register(_ shortcut: Shortcut, caller: String, action: @escaping @MainActor () -> Void)
    func unregister(caller: String)
}

extension HotKeyCenter: StackHotKeyRegistering {}
