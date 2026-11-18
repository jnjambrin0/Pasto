/// What the welcome needs to know about suggestions, on a Mac that can run them. The app hands
/// one in; without it the welcome has no suggestions step.
public struct OnboardingSuggestions {
    /// Apple Intelligence is on, whether or not its model has finished downloading.
    let isModelEnabled: @MainActor () -> Bool

    public init(isModelEnabled: @escaping @MainActor () -> Bool) {
        self.isModelEnabled = isModelEnabled
    }
}
