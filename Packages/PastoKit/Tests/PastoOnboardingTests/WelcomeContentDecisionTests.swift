import PastoFoundation
@testable import PastoOnboarding
import Testing

/// Only a first launch that has not had it offers the welcome content.
struct WelcomeContentDecisionTests {
    @Test func aFirstLaunchSeeds() {
        let decision = WelcomeContentDecision(lastLaunchedVersion: nil, wasSeeded: false)

        #expect(decision.isFirstLaunch)
        #expect(decision.shouldSeed)
    }

    @Test(arguments: [AppVersion(major: 1, minor: 0, patch: 2), AppVersion(major: 1, minor: 1)])
    func anUpdateDoesNotSeed(previous: AppVersion) {
        #expect(!WelcomeContentDecision(lastLaunchedVersion: previous, wasSeeded: false).shouldSeed)
    }

    @Test func aFirstLaunchThatAlreadyHadItDoesNotSeedAgain() {
        // A first launch cut short after the content went in, or settings left behind.
        #expect(!WelcomeContentDecision(lastLaunchedVersion: nil, wasSeeded: true).shouldSeed)
    }

    @Test func anyOtherLaunchDoesNotSeed() {
        #expect(!WelcomeContentDecision(lastLaunchedVersion: AppVersion(major: 2), wasSeeded: true).shouldSeed)
    }
}
