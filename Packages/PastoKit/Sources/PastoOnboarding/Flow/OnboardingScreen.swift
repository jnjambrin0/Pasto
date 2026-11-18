/// The steps of the welcome, in the order they are shown. The raw value is what is saved to
/// resume a welcome left halfway.
nonisolated enum OnboardingScreen: String, CaseIterable, Sendable {
    case intro
    case directPaste = "direct_paste"
    case pasteboardAccess = "pasteboard_access"
    case suggestions
    case setup

    /// The steps of one run. Each permission has its step whether or not it is granted — the
    /// step shows which — so that every run has the same steps and a run cut short, by System
    /// Settings' "Quit & Reopen" for one, comes back to the step it was on. Suggestions have a
    /// step only on a Mac that can run them.
    static func list(offersSuggestions: Bool) -> [OnboardingScreen] {
        allCases.filter { $0 != .suggestions || offersSuggestions }
    }
}
