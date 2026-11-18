/// What Settings › Intelligence needs to know about suggestions, which live in a module Settings
/// does not import: the app hands it over from its suggestions provider.
///
/// The two state closures are read while the pane draws. When they read observable state, as the
/// provider's is, the pane and the sidebar follow its changes while the window is open.
public struct SuggestionsAvailability {
    /// The Mac can run the language model. Without it there is no Suggestions section, and
    /// Intelligence has nothing to show.
    public var isSupported: Bool
    /// Apple Intelligence is on, whether or not its model has finished downloading. While it is
    /// off, the pane says suggestions need it.
    public var isModelEnabled: () -> Bool
    /// Suggestions are on, and so is Apple Intelligence, but screen recording access is missing:
    /// the pane offers to ask for it and the sidebar flags Intelligence.
    public var isScreenAccessMissing: () -> Bool
    /// Shows the window that asks for screen recording access.
    public var requestScreenAccess: () -> Void

    public init(
        isSupported: Bool,
        isModelEnabled: @escaping () -> Bool,
        isScreenAccessMissing: @escaping () -> Bool,
        requestScreenAccess: @escaping () -> Void
    ) {
        self.isSupported = isSupported
        self.isModelEnabled = isModelEnabled
        self.isScreenAccessMissing = isScreenAccessMissing
        self.requestScreenAccess = requestScreenAccess
    }

    /// What Settings assumes until the app says otherwise: a Mac without suggestions.
    public static let unsupported = SuggestionsAvailability(
        isSupported: false,
        isModelEnabled: { false },
        isScreenAccessMissing: { false },
        requestScreenAccess: {}
    )
}
