import PastoFoundation
@testable import PastoOnboarding
import Testing

struct OnboardingNavigationTests {
    private let allScreens: [OnboardingScreen] = [.intro, .directPaste, .pasteboardAccess, .suggestions, .setup]

    // MARK: Screens

    @Test func everyRunHasEveryPermissionStepAndQuickStartLast() {
        #expect(OnboardingScreen.list(offersSuggestions: true) == allScreens)
    }

    @Test func aMacWithoutSuggestionsHasNoSuggestionsStep() {
        #expect(OnboardingScreen.list(offersSuggestions: false) == [.intro, .directPaste, .pasteboardAccess, .setup])
    }

    // MARK: Going forward

    @Test func goesThroughTheScreensInOrderSavingThePath() {
        var navigation = OnboardingNavigation(screens: allScreens, resumingFrom: nil)
        #expect(navigation.current == .intro)

        #expect(navigation.advance(from: .intro) == .inProgress(navigationPath: ["direct_paste"]))
        #expect(navigation.current == .directPaste)
        #expect(navigation.advance(from: .directPaste) == .inProgress(navigationPath: ["direct_paste", "pasteboard_access"]))
        #expect(navigation.advance(from: .pasteboardAccess) == .inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions"]))
        #expect(navigation.advance(from: .suggestions) == .inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions", "setup"]))
        #expect(navigation.current == .setup)
    }

    @Test func goingOnFromTheLastScreenCompletesAndStaysThere() {
        var navigation = OnboardingNavigation(screens: [.intro, .setup], resumingFrom: nil)
        _ = navigation.advance(from: .intro)

        #expect(navigation.advance(from: .setup) == .completed)
        #expect(navigation.current == .setup)
    }

    @Test func goingOnTwiceFromTheSameScreenGoesOnOnce() {
        var navigation = OnboardingNavigation(screens: allScreens, resumingFrom: nil)

        _ = navigation.advance(from: .intro)

        #expect(navigation.advance(from: .intro) == nil)
        #expect(navigation.current == .directPaste)
    }

    /// A permission step finishes by itself a moment after the grant; if the user has gone on
    /// meanwhile, that late call must not take them back.
    @Test func aScreenLeftBehindCannotMoveTheWelcome() {
        var navigation = OnboardingNavigation(screens: allScreens, resumingFrom: nil)
        _ = navigation.advance(from: .intro)
        _ = navigation.advance(from: .directPaste)
        _ = navigation.advance(from: .pasteboardAccess)

        #expect(navigation.advance(from: .directPaste) == nil)
        #expect(navigation.current == .suggestions)
    }

    // MARK: Resuming

    @Test func resumesOnTheScreenItWasLeftOn() {
        let navigation = OnboardingNavigation(
            screens: allScreens,
            resumingFrom: .inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions"])
        )

        #expect(navigation.current == .suggestions)
    }

    /// System Settings quits Pasto to apply screen recording access: the new run has the same
    /// steps, so it comes back to suggestions even though the permission steps are now granted.
    @Test func comesBackToTheSuggestionsStepAfterQuitAndReopen() {
        var navigation = OnboardingNavigation(
            screens: OnboardingScreen.list(offersSuggestions: true),
            resumingFrom: .inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions"])
        )

        #expect(navigation.current == .suggestions)
        #expect(navigation.advance(from: .suggestions) == .inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions", "setup"]))
    }

    /// After "Quit & Reopen", Getting Started is shown again on its suggestions step only if it
    /// was left there; a finished one sends the user the panel's way.
    @Test func tellsWhetherTheWelcomeWaitsOnSuggestions() {
        let ephemeral = EphemeralDefaults()
        let config = ConfigStore(defaults: ephemeral.defaults)
        #expect(!config.isWelcomeOnSuggestionsStep)

        config.set(JSONConfigValue(.inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions"])), for: .onboardingState)
        #expect(config.isWelcomeOnSuggestionsStep)

        config.set(JSONConfigValue(.inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions", "setup"])), for: .onboardingState)
        #expect(!config.isWelcomeOnSuggestionsStep)

        config.set(JSONConfigValue(.completed), for: .onboardingState)
        #expect(!config.isWelcomeOnSuggestionsStep)
    }

    @Test func resumesWhereThePathStillHoldsWhenAScreenOnItIsGone() {
        let navigation = OnboardingNavigation(
            screens: [.intro, .directPaste, .pasteboardAccess, .setup],
            resumingFrom: .inProgress(navigationPath: ["direct_paste", "pasteboard_access", "suggestions", "setup"])
        )

        #expect(navigation.current == .pasteboardAccess)
    }

    @Test(arguments: [
        OnboardingState.completed,
        .inProgress(navigationPath: []),
        .inProgress(navigationPath: ["paywall"]),
    ])
    func startsOverWhenThereIsNothingToResume(state: OnboardingState) {
        #expect(OnboardingNavigation(screens: allScreens, resumingFrom: state).current == .intro)
    }

    @Test func aResumedRunSavesTheWholePath() {
        var navigation = OnboardingNavigation(screens: allScreens, resumingFrom: .inProgress(navigationPath: ["direct_paste"]))

        #expect(navigation.advance(from: .directPaste) == .inProgress(navigationPath: ["direct_paste", "pasteboard_access"]))
    }
}
