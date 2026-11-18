import PastoFoundation

extension ConfigKey where Value == String {
    /// The version that got to the end of its launch last, as text; empty until one does.
    nonisolated static var lastLaunchedVersion: ConfigKey<String> {
        ConfigKey("lastLaunchedVersion", default: "")
    }
}

extension ConfigStore {
    /// The version that got to the end of its launch last; nil on a first launch.
    public nonisolated var lastLaunchedVersion: AppVersion? {
        AppVersion(value(for: .lastLaunchedVersion))
    }

    /// Call once the launch is over, onboarding included: a launch cut short is a first launch
    /// again the next time.
    public nonisolated func recordLaunch(of version: AppVersion) {
        set(version.description, for: .lastLaunchedVersion)
    }
}
