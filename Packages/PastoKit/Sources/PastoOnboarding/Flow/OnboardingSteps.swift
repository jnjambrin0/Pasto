import PastoPermissions

/// The state of every step of one run, made once when the window is, before the first step
/// shows: whatever asks the system something — the shortcut's text, the keyboard layout, the
/// history's capacity, the state of each permission — is asked then, so that going from one
/// step to the next only swaps views.
struct OnboardingSteps {
    let accessibility: AccessRequestModel
    let pasteboard: AccessRequestModel
    /// Nil on a Mac that cannot run suggestions.
    let suggestions: SuggestionsStepModel?
    let quickStart: QuickStartModel

    /// The step's title, which VoiceOver says as the welcome comes to it.
    func title(of screen: OnboardingScreen) -> String {
        switch screen {
        case .intro: OnboardingStrings.introTitle
        case .directPaste: accessibility.permission.title
        case .pasteboardAccess: pasteboard.permission.title
        case .suggestions: OnboardingStrings.suggestionsTitle
        case .setup: OnboardingStrings.quickStartTitle
        }
    }
}
