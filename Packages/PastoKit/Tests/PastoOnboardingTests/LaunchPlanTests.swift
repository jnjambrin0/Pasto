import Foundation
import PastoFoundation
@testable import PastoOnboarding
import Testing

struct LaunchPlanTests {
    private let current = AppVersion(major: 2, minor: 3, patch: 1)

    @Test func withoutAPreviousLaunchItIsAFirstLaunch() {
        let plan = LaunchPlan(lastLaunchedVersion: nil, currentVersion: current)

        #expect(plan.isFirstLaunch)
        #expect(!plan.isUpdated)
        #expect(plan.runsOnboarding)
        #expect(plan.showsPanelWhenFinished)
    }

    @Test(arguments: [AppVersion(major: 1, minor: 9, patch: 9), AppVersion(major: 2, minor: 2, patch: 7)])
    func aLowerMajorOrMinorIsAnUpdate(previous: AppVersion) {
        let plan = LaunchPlan(lastLaunchedVersion: previous, currentVersion: current)

        #expect(!plan.isFirstLaunch)
        #expect(plan.isUpdated)
        #expect(!plan.runsOnboarding)
        #expect(!plan.showsPanelWhenFinished)
    }

    @Test(arguments: [
        AppVersion(major: 2, minor: 3),
        AppVersion(major: 2, minor: 3, patch: 1),
        AppVersion(major: 2, minor: 4),
        AppVersion(major: 3),
    ])
    func aPatchTheSameVersionOrANewerOneIsNotAnUpdate(previous: AppVersion) {
        let plan = LaunchPlan(lastLaunchedVersion: previous, currentVersion: current)

        #expect(!plan.isFirstLaunch)
        #expect(!plan.isUpdated)
    }

    @Test func theLaunchedVersionIsRememberedOnceRecorded() {
        let ephemeral = EphemeralDefaults()
        let config = ConfigStore(defaults: ephemeral.defaults)

        #expect(config.lastLaunchedVersion == nil)

        config.recordLaunch(of: current)

        #expect(config.lastLaunchedVersion == current)
    }
}
