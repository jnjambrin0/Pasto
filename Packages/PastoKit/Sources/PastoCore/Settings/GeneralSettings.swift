import PastoFoundation

// Settings that more than one feature reads, and their `UserDefaults` keys. A setting used by a
// single module is declared next to its use instead.

extension ConfigKey where Value == Bool {
    /// Play a sound when something is copied or pasted.
    public static var isSoundEffectsEnabled: ConfigKey<Bool> {
        ConfigKey("isSoundEffectsEnabled", default: true)
    }

    /// "Show in Menu Bar".
    public static var isStatusItemEnabled: ConfigKey<Bool> {
        ConfigKey("isStatusItemEnabled", default: true)
    }

}
