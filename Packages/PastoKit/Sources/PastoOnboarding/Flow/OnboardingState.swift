import PastoFoundation

/// How far onboarding got, saved after every step.
nonisolated enum OnboardingState: Codable, Equatable, Sendable {
    /// The screens gone forward to, after the first one, by identifier.
    case inProgress(navigationPath: [String])
    case completed
}

extension ConfigStore {
    /// Whether a welcome left halfway is waiting on its suggestions step, where it will open
    /// again: System Settings quit Pasto there to apply screen recording access.
    public var isWelcomeOnSuggestionsStep: Bool {
        guard case .inProgress(let path) = value(for: .onboardingState).value else { return false }
        return path.last == OnboardingScreen.suggestions.rawValue
    }
}

extension ConfigKey where Value == JSONConfigValue<OnboardingState?> {
    nonisolated static var onboardingState: ConfigKey<JSONConfigValue<OnboardingState?>> {
        ConfigKey("onboardingState", default: JSONConfigValue(nil))
    }
}
