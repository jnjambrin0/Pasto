import PastoFoundation

extension ConfigKey where Value == Bool {
    /// "Paste Items: to active app". When off, choosing an item only copies it.
    public static let isDirectPasteEnabled = ConfigKey("isDirectPasteEnabled", default: true)

    /// "Always paste as plain text". Read by whoever turns a gesture into `RestoreOptions`, with
    /// `RestoreOptions.applying(alwaysPlainText:)`.
    public static let isPasteAsPlainTextEnabled = ConfigKey("isPasteAsPlainTextEnabled", default: false)
}
