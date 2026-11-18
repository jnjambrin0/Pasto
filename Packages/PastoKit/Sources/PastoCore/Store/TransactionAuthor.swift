/// Who made a change to the store. Recorded in persistent history, so that consumers of
/// `HistoryTailer` can tell their own writes from everybody else's.
public enum TransactionAuthor: String, Sendable {
    case capture
    case user
    case sync
    case mcp
    case intents
    case maintenance
}
