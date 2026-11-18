import PastoCore

/// What the Paste Stack needs from the rest of the app. The stack reads the store, pastes and
/// copies only through these.
public struct StackDependencies {
    public typealias DraggingContents = @MainActor (_ ids: [ItemID], _ options: RestoreOptions) -> [ItemID: [PasteboardItemSnapshot]]
    public typealias Record = @MainActor (_ content: [PasteboardItemSnapshot]) async -> ItemID?

    /// The existing items among the given identifiers, in the order given.
    public var items: @MainActor (_ ids: [ItemID]) -> [Item]

    /// Puts the items on the pasteboard and sends the paste keystroke to the frontmost
    /// application, without consulting the "paste to active app" setting. Returns false when
    /// nothing was pasted — no Accessibility permission, no such items —, in which case the rows
    /// stay in the stack.
    public var paste: @MainActor (_ ids: [ItemID], _ options: RestoreOptions) -> Bool

    /// Asks the frontmost application to copy, by sending it the copy keystroke. Returns true
    /// once the keystroke has been asked for, even if it could not be sent; returns false, after
    /// telling the user why, when Pasto may not send keystrokes — the stack then does not open.
    public var copy: @MainActor () -> Bool

    /// What the history captures from now on.
    public var captureEvents: @MainActor () async -> AsyncStream<CaptureEvent>

    /// Emits whenever items may have changed or gone.
    public var storeChanges: @MainActor () -> AsyncStream<Void>

    /// What a row dragged out of the panel gives other applications: for every item, the
    /// pasteboard items a paste of that item alone would write (`ItemRestorer.draggingContents`).
    /// Unset, rows can still be dragged around the panel but other applications get nothing.
    public var draggingContents: DraggingContents?

    /// Stores what another application dropped on the panel as an item, and returns it; `nil`
    /// when nothing could be stored. Unset, the panel only takes items dragged from Pasto.
    public var record: Record?

    public init(
        items: @escaping @MainActor (_ ids: [ItemID]) -> [Item],
        paste: @escaping @MainActor (_ ids: [ItemID], _ options: RestoreOptions) -> Bool,
        copy: @escaping @MainActor () -> Bool,
        captureEvents: @escaping @MainActor () async -> AsyncStream<CaptureEvent>,
        storeChanges: @escaping @MainActor () -> AsyncStream<Void>,
        draggingContents: DraggingContents? = nil,
        record: Record? = nil
    ) {
        self.items = items
        self.paste = paste
        self.copy = copy
        self.captureEvents = captureEvents
        self.storeChanges = storeChanges
        self.draggingContents = draggingContents
        self.record = record
    }
}
