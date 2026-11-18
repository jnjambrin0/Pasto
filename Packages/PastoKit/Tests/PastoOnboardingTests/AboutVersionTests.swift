@testable import PastoOnboarding
import Testing

/// The version line of the About window.
struct AboutVersionTests {
    @Test func theBuildFollowsTheVersionInParentheses() {
        #expect(AboutVersion.text(shortVersion: "1.0", build: "42") == "1.0 (42)")
    }

    @Test func withoutABuildTheVersionStandsAlone() {
        #expect(AboutVersion.text(shortVersion: "1.0", build: nil) == "1.0")
        #expect(AboutVersion.text(shortVersion: "1.0", build: "") == "1.0")
    }

    @Test func withoutAVersionThereIsNothingToShow() {
        #expect(AboutVersion.text(shortVersion: nil, build: "42") == nil)
        #expect(AboutVersion.text(shortVersion: "", build: "42") == nil)
    }
}
