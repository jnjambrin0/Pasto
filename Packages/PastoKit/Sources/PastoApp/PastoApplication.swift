import AppKit

/// Process entry point. The app target is a shell whose `main.swift` only calls `PastoApplication.main()`.
public enum PastoApplication {
    private static let delegate = AppDelegate()

    public static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        // Pasto is a menu bar agent (LSUIElement): it never shows a Dock icon.
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
