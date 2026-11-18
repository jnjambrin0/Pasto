/// Where onboarding is: it only goes forward, one screen at a time.
nonisolated struct OnboardingNavigation: Equatable {
    /// Never empty.
    let screens: [OnboardingScreen]
    /// The screens gone forward to, after the first one; the last is the one on show.
    private var path: [OnboardingScreen] = []

    /// - Parameters:
    ///   - screens: The screens of this run, which may differ from those of the run that saved
    ///     `state`: a permission may have been granted, or taken away, since.
    ///   - state: What a previous run that did not finish left saved. Its path is kept up to the
    ///     first screen this run does not have.
    init(screens: [OnboardingScreen], resumingFrom state: OnboardingState?) {
        self.screens = screens
        guard case .inProgress(let savedPath) = state else { return }
        for identifier in savedPath {
            guard let screen = OnboardingScreen(rawValue: identifier), screens.contains(screen) else { break }
            path.append(screen)
        }
    }

    var current: OnboardingScreen {
        path.last ?? screens[0]
    }

    /// Goes on to the screen after `screen`, the one asking. Only the screen on show goes on:
    /// asking twice from the same screen goes there once, and a screen left behind — one that
    /// finishes by itself a moment after its permission is granted, say — changes nothing.
    /// Returns what to save, or nil when there is nothing new to save.
    mutating func advance(from screen: OnboardingScreen) -> OnboardingState? {
        guard screen == current, let index = screens.firstIndex(of: screen) else { return nil }
        guard index + 1 < screens.count else { return .completed }
        let next = screens[index + 1]
        guard path.last != next else { return nil }
        path.append(next)
        return .inProgress(navigationPath: path.map(\.rawValue))
    }
}
