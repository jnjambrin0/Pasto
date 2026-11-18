/// How a window that asks for a permission ended.
public enum PermissionOutcome: Equatable, Sendable {
    /// The permission was granted while the window was open.
    case success
    /// The user closed the window, or skipped the step.
    case cancel
}
