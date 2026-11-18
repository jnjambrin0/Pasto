/// Whether the on-device language model can be used.
public enum LanguageModelAvailability: Sendable, Equatable {
    /// There is no on-device model on this system.
    case unsupported
    /// The Mac cannot run Apple Intelligence.
    case deviceNotEligible
    /// Apple Intelligence is turned off.
    case appleIntelligenceNotEnabled
    /// Apple Intelligence is on, but the model is not ready yet (still downloading, for one).
    case modelNotReady
    case available

    /// The Mac can run the model at all: suggestions exist on it.
    public var isSupported: Bool {
        self != .unsupported && self != .deviceNotEligible
    }

    /// Apple Intelligence is on, whether or not the model has finished downloading: suggestions
    /// are offered.
    public var isEnabled: Bool {
        self == .modelNotReady || self == .available
    }
}
