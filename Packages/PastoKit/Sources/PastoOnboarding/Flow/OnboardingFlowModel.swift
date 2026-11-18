import Observation
import os
import PastoFoundation

/// Onboarding's position as SwiftUI state, saved after every step so that a run cut short
/// resumes where it was.
///
/// Each step's way forward is timed with a signpost ("Onboarding step", category `app`): from
/// the button to the next step's view being in place, the moment the slide starts. It should
/// stay well under 100 ms.
@Observable
final class OnboardingFlowModel {
    private var navigation: OnboardingNavigation
    private let config: ConfigStore
    /// Let go once called: finishing happens once, however often the last screen asks.
    @ObservationIgnored private var onFinish: (() -> Void)?
    @ObservationIgnored private var step: (state: OSSignpostIntervalState, from: OnboardingScreen, start: ContinuousClock.Instant)?
    @ObservationIgnored private let signposter = OSSignposter(logger: Log.logger(.app))
    @ObservationIgnored private let log = Log.logger(.app)

    init(screens: [OnboardingScreen], config: ConfigStore, onFinish: @escaping () -> Void) {
        navigation = OnboardingNavigation(screens: screens, resumingFrom: config.value(for: .onboardingState).value)
        self.config = config
        self.onFinish = onFinish
    }

    var current: OnboardingScreen {
        navigation.current
    }

    var screens: [OnboardingScreen] {
        navigation.screens
    }

    /// Goes on from `screen`, the screen whose button was pressed.
    func advance(from screen: OnboardingScreen) {
        guard let state = navigation.advance(from: screen) else { return }
        if state != .completed {
            step = (signposter.beginInterval("Onboarding step", "from \(screen.rawValue, privacy: .public)"), screen, .now)
        }
        config.set(JSONConfigValue(state), for: .onboardingState)
        if state == .completed, let onFinish {
            self.onFinish = nil
            onFinish()
        }
    }

    /// The step on show has its view in place.
    func screenDidAppear(_ screen: OnboardingScreen) {
        guard let step, screen == current else { return }
        self.step = nil
        signposter.endInterval("Onboarding step", step.state, "to \(screen.rawValue, privacy: .public)")
        let elapsed = ContinuousClock.now - step.start
        log.info("Onboarding: \(step.from.rawValue, privacy: .public) → \(screen.rawValue, privacy: .public) in \(elapsed.milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
    }
}

extension Duration {
    fileprivate var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
