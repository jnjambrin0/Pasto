/// Whether a launch offers the welcome content to the store.
///
/// The content is seeded only at the end of a first launch's welcome flow, and only into a store
/// without pinboards. The first half is decided here, before anything is written; the second
/// inside the write itself (`WritingContext.seedWelcomeContent(_:)`), so that nothing can slip
/// in between the check and the content.
nonisolated struct WelcomeContentDecision: Equatable, Sendable {
    /// No version got to the end of a launch before: a new installation, or one whose first
    /// launch was cut short. Updating from an earlier version is not one.
    let isFirstLaunch: Bool
    /// This installation already had the content, or turned it down (`isWelcomeContentSeeded`).
    let wasSeeded: Bool

    init(lastLaunchedVersion: AppVersion?, wasSeeded: Bool) {
        isFirstLaunch = lastLaunchedVersion == nil
        self.wasSeeded = wasSeeded
    }

    var shouldSeed: Bool {
        isFirstLaunch && !wasSeeded
    }
}
