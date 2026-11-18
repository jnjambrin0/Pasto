import PastoFoundation

extension ConfigKey where Value == Bool {
    /// Whether this installation has had its welcome content: stored, or turned down by a store
    /// that already had pinboards. Never cleared, so content the user deletes does not come back.
    nonisolated static var isWelcomeContentSeeded: ConfigKey<Bool> {
        ConfigKey("isWelcomeContentSeeded", default: false)
    }
}
