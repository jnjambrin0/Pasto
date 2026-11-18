/// What `HistoryManager` tells the rest of the app while it captures.
public enum CaptureEvent: Sendable, Equatable {
    /// A copy reached the history.
    case captured(PasteboardCapture)
    /// A copy could not be read because the user has not allowed Pasto to read the pasteboard
    /// ("Paste from Other Apps" is not "Always Allow"). Sent for every copy that is missed.
    case pasteboardAccessNeeded
}

/// One capture.
public struct PasteboardCapture: Sendable, Equatable {
    public let itemID: ItemID
    public let itemType: ItemType
    /// The content was already in the history, and that item went back to its front instead of
    /// a new one being created. Content that only lived on a pinboard was not. No copy sound is
    /// played for such a capture while the Paste Stack is open.
    public let wasInHistory: Bool
    /// The history has a different newest item than before this capture. Copying again what is
    /// already the newest item leaves it as it was.
    public let didChangeNewestItem: Bool

    public init(itemID: ItemID, itemType: ItemType, wasInHistory: Bool, didChangeNewestItem: Bool) {
        self.itemID = itemID
        self.itemType = itemType
        self.wasInHistory = wasInHistory
        self.didChangeNewestItem = didChangeNewestItem
    }
}
