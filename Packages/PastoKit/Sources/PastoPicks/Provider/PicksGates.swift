/// When suggestions are offered and what they still need.
struct PicksGates: Equatable {
    /// The Mac can run the language model; decided once, at launch.
    var isSupported: Bool
    /// The "Intelligent clipboard" setting.
    var isSettingOn: Bool
    /// Apple Intelligence is on, whether or not the model has finished downloading.
    var isModelEnabled: Bool
    var hasScreenAccess: Bool

    /// The toolbar offers the suggestions button.
    var isOffered: Bool {
        isSupported && isSettingOn && isModelEnabled
    }

    /// Suggestions are offered but cannot work: the strip asks for screen recording access.
    var isScreenAccessMissing: Bool {
        isOffered && !hasScreenAccess
    }
}
