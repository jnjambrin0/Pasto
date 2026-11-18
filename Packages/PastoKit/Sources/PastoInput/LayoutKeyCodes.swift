import AppKit

/// Key codes of characters on the current keyboard layout, remembered until the layout changes.
///
/// Key equivalents inside the panel are compared by "the key that types this character on the
/// active layout", so every key press would otherwise scan the whole layout.
@MainActor
public final class LayoutKeyCodes {
    public static let shared = LayoutKeyCodes()

    private var keyCodes: [Character: CGKeyCode?] = [:]
    private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyCodes.removeAll() }
        }
    }

    public func keyCode(for character: Character) -> CGKeyCode? {
        if let known = keyCodes[character] { return known }
        let keyCode = KeyCodeResolver.keyCode(for: character)
        keyCodes[character] = keyCode
        return keyCode
    }
}
