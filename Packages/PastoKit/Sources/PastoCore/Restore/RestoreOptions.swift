/// How the items being restored are put back on the pasteboard.
public struct RestoreOptions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Items that are neither text nor links (images, files, colors) are written as their plain
    /// text; the ones that have none are not written at all.
    public static let nonTextAsPlainText = RestoreOptions(rawValue: 1 << 0)
    /// Text and link items are written as plain text, without their formatting.
    public static let textAsPlainText = RestoreOptions(rawValue: 1 << 1)
    /// Everything as plain text: what the plain-text modifier and "Paste as Plain Text" ask for.
    public static let plainText: RestoreOptions = [.nonTextAsPlainText, .textAsPlainText]

    /// The options a paste from the main panel runs with: what the gesture asked for, plus the
    /// "always paste as plain text" setting.
    ///
    /// The setting only ever adds `textAsPlainText`: images and files keep their own form, and the
    /// modifier cannot bring the formatting back while the setting is on. The Paste Stack does not
    /// go through here: it passes the state of its own plain-text switch.
    public func applying(alwaysPlainText: Bool) -> RestoreOptions {
        alwaysPlainText ? union(.textAsPlainText) : self
    }
}
