/// Whether a transaction's changes reached the store (`StoreWriter.outcomes()`).
public enum WriteOutcome: Sendable, Equatable {
    case saved
    /// The store could not save: the disk is full, the database cannot be written…
    case failed

    /// A transaction rejected for what it asked — an item that is gone, an operation that is
    /// not allowed — says nothing about the store; anything else that stops it does.
    static func isFailureToSave(_ error: any Error) -> Bool {
        !(error is StoreError) && !(error is CancellationError)
    }
}
