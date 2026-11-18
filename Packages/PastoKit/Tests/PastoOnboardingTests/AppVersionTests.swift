@testable import PastoOnboarding
import Testing

struct AppVersionTests {
    @Test func readsOneToThreeNumbers() {
        #expect(AppVersion("7") == AppVersion(major: 7))
        #expect(AppVersion("7.1") == AppVersion(major: 7, minor: 1))
        #expect(AppVersion("7.1.3") == AppVersion(major: 7, minor: 1, patch: 3))
    }

    @Test(arguments: ["", "7.", "7.1.0.2", "7.x", "-1.0", "beta"])
    func rejectsWhatIsNotAVersion(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func ordersByMajorThenMinorThenPatch() {
        #expect(AppVersion(major: 1, minor: 9, patch: 9) < AppVersion(major: 2))
        #expect(AppVersion(major: 2, minor: 0, patch: 9) < AppVersion(major: 2, minor: 1))
        #expect(AppVersion(major: 2, minor: 1) < AppVersion(major: 2, minor: 1, patch: 1))
    }

    @Test func isWrittenInFull() {
        #expect(AppVersion(major: 7, minor: 1).description == "7.1.0")
    }
}
