/// Where the user is about to paste: the application the panel opened over, the kind of field
/// once known, and whether the system is in secure input — a password field has the keyboard.
public struct DestinationContext: Sendable, Hashable, Codable {
    public var appBundleIdentifier: String
    public var fieldKind: FieldKind?
    public var isSecureInput: Bool

    public init(appBundleIdentifier: String, fieldKind: FieldKind? = nil, isSecureInput: Bool) {
        self.appBundleIdentifier = appBundleIdentifier
        self.fieldKind = fieldKind
        self.isSecureInput = isSecureInput
    }
}
