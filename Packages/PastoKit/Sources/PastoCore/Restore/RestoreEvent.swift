/// Items were put back on the pasteboard: what `ItemRestorer` reports after every restore, and
/// what the paste sound is played on.
public struct RestoreEvent: Sendable, Equatable {
    /// The restored items, in the order they were written.
    public let itemIDs: [ItemID]
}
