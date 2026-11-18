import os
import PastoFoundation
import PastoInput
import PastoOnboarding

/// The shortcuts of a new installation: applied once, at launch and before onboarding, so that
/// Quick Start shows the activation shortcut that will really work.
/// At every launch, the same test finds the user's shortcuts that something else has taken.
enum InitialShortcuts {
    @MainActor
    static func apply(to config: ConfigStore, hotKeys: HotKeyCenter) {
        guard !config.value(for: .isInitialShortcutsMigrationCompleted) else { return }
        let otherManagers = KnownClipboardManager.running()
        ShortcutDefaults.applyInitialShortcuts(to: config, isAvailable: availability(hotKeys: hotKeys, otherManagers: otherManagers))
        let activation = config.shortcut(for: .activationShortcut).map { ShortcutDisplay.string(for: $0) } ?? "none"
        let stack = config.shortcut(for: .pasteStackShortcut).map { ShortcutDisplay.string(for: $0) } ?? "none"
        Log.logger(.shortcut).info("""
            Initial shortcuts: activation \(activation, privacy: .public), stack \(stack, privacy: .public); \
            clipboard managers open: \(otherManagers.map(\.name), privacy: .public)
            """)
    }

    /// The user's system-wide shortcuts that something else answers to now. To be asked before
    /// Pasto registers them: a combination Pasto holds counts as free.
    @MainActor
    static func takenShortcuts(in config: ConfigStore, hotKeys: HotKeyCenter) -> [ShortcutKey] {
        let taken = ShortcutDefaults.takenShortcuts(
            in: config, isAvailable: availability(hotKeys: hotKeys, otherManagers: KnownClipboardManager.running())
        )
        if !taken.isEmpty {
            Log.logger(.shortcut).notice("Shortcuts taken by something else: \(taken.map(\.name), privacy: .public)")
        }
        return taken
    }

    /// A combination is taken when macOS has it among its keyboard shortcuts, when another app
    /// holds it as a hot key, or when a clipboard manager that uses it by default is open.
    @MainActor
    private static func availability(hotKeys: HotKeyCenter, otherManagers: [KnownClipboardManager]) -> (Shortcut) -> Bool {
        let system = ShortcutValidator.current()
        return { shortcut in
            // Without a key, the validator looks at macOS's shortcuts only, not Pasto's menus.
            system.conflict(for: shortcut, key: nil) == nil
                && hotKeys.isAvailable(shortcut)
                && !otherManagers.contains { $0.shortcuts.contains(shortcut) }
        }
    }
}
