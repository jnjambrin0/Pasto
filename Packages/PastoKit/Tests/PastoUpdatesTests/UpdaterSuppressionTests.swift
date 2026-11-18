import PastoUpdates
import Testing

/// When the updater may start.
struct UpdaterSuppressionTests {
    private let release: [String: Any] = [
        "SUFeedURL": "https://pasto.app/appcast.xml",
        "SUPublicEDKey": "A9j5LwwY+Qw7dRQtPQQ/N/6YCd5/56DT6jazquGKx/s=",
    ]

    @Test func aReleaseBuildWithFeedAndKeyLooksForUpdates() {
        #expect(UpdaterSuppression.reason(infoDictionary: release, isDebugBuild: false, isDevelopmentRun: false) == nil)
    }

    @Test func debugBuildsAndDevelopmentRunsNeverDo() {
        #expect(UpdaterSuppression.reason(infoDictionary: release, isDebugBuild: true, isDevelopmentRun: false) == .debugBuild)
        #expect(UpdaterSuppression.reason(infoDictionary: release, isDebugBuild: false, isDevelopmentRun: true) == .developmentRun)
    }

    /// A Debug build expands the feed setting, which only Release defines, to an empty string.
    @Test(arguments: [nil, "", "  ", "http://pasto.app/appcast.xml", "$(PASTO_FEED_URL)"])
    func aBuildWithoutAnHTTPSFeedCannot(feed: String?) {
        var info = release
        info["SUFeedURL"] = feed

        #expect(UpdaterSuppression.reason(infoDictionary: info, isDebugBuild: false, isDevelopmentRun: false) == .missingFeedURL)
    }

    @Test(arguments: [nil, ""])
    func aBuildWithoutThePublicKeyCannot(key: String?) {
        var info = release
        info["SUPublicEDKey"] = key

        #expect(UpdaterSuppression.reason(infoDictionary: info, isDebugBuild: false, isDevelopmentRun: false) == .missingPublicKey)
    }
}
