/// Why a write was rejected. The transaction it belonged to is rolled back as a whole.
public enum StoreError: Error, Equatable, Sendable {
    case itemNotFound
    case listNotFound
    case cannotDeleteClipboardHistory
    case invalidOperation(String)
}
