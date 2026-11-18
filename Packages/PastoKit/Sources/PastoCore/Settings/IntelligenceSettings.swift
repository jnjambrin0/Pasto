import PastoFoundation

// Settings › Intelligence.

extension ConfigKey where Value == Bool {
    /// "Intelligent Clipboard": suggestions for what is about to be pasted.
    public static var isPicksEnabled: ConfigKey<Bool> {
        ConfigKey("isPicksEnabled", default: true)
    }
}
