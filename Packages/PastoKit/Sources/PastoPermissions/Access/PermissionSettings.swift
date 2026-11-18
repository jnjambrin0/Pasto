import PastoFoundation

extension ConfigKey where Value == Bool {
    /// Whether Pasto already asked the system for screen recording access. The system shows its
    /// alert only the first time, so later requests go to System Settings instead.
    static var isScreenRecordingAccessRequested: ConfigKey<Bool> {
        ConfigKey("isScreenRecordingAccessRequested", default: false)
    }
}

extension ConfigKey where Value == Double {
    /// When `ScreenCaptureCheck` last went through, in seconds since the reference date; 0 for never.
    static var screenCaptureConfirmationTime: ConfigKey<Double> {
        ConfigKey("screenCaptureConfirmationTime", default: 0)
    }
}
