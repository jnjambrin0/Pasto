/// When capture finds pasteboard access short of "always allow", whether to put the modal
/// window that asks for it up now.
///
/// Capture reports the missing access on every copy, and a window that takes the focus from
/// whatever the user is typing on every copy is worse than no Pasto at all. So the window goes
/// up once per launch at most, never over another modal window or the open panel, and never
/// when the user chose "Deny" in System Settings: that was their decision. Afterwards the
/// notice card in the panel and the dimmed menu bar icon are the reminder.
nonisolated struct PasteboardAccessReminder: Sendable {
    private(set) var hasAsked = false

    /// True at most once: the caller then shows the window.
    mutating func shouldAsk(isDenied: Bool, isPanelOpen: Bool, isModalWindowUp: Bool) -> Bool {
        guard !hasAsked, !isDenied, !isPanelOpen, !isModalWindowUp else { return false }
        hasAsked = true
        return true
    }
}
