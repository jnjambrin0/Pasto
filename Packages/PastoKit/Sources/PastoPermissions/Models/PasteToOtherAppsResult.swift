/// How the user answered "do you want Pasto to paste for you?"
public enum PasteToOtherAppsResult: Equatable, Sendable {
    /// Go on to granting Accessibility access. Nothing is pasted or copied.
    case enableAccessibilityAccess
    /// Only copy the item; with `doNotAskAgain`, from now on too.
    case copyToClipboard(doNotAskAgain: Bool)
}
