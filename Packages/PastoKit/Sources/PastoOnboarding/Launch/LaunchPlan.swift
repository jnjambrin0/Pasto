/// What a launch does besides starting the app, decided from the version that ran last.
public nonisolated struct LaunchPlan: Equatable, Sendable {
    /// Nothing ran before on this Mac, or its first launch never got to the end.
    public let isFirstLaunch: Bool
    /// The version that ran last had a lower major or minor number. A patch does not count.
    public let isUpdated: Bool

    /// - Parameter lastLaunchedVersion: The version recorded at the end of the previous launch;
    ///   nil when there was none.
    public init(lastLaunchedVersion: AppVersion?, currentVersion: AppVersion) {
        guard let lastLaunchedVersion else {
            isFirstLaunch = true
            isUpdated = false
            return
        }
        isFirstLaunch = false
        isUpdated = (lastLaunchedVersion.major, lastLaunchedVersion.minor) < (currentVersion.major, currentVersion.minor)
    }

    /// Onboarding runs before anything else, and the launch waits for it. The notice cards are
    /// seeded when it ends.
    public var runsOnboarding: Bool {
        isFirstLaunch
    }

    /// A first launch ends with the panel on screen; any other leaves Pasto in the background.
    public var showsPanelWhenFinished: Bool {
        isFirstLaunch
    }
}
