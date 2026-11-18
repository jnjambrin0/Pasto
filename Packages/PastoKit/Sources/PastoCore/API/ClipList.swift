/// The clipboard history or a pinboard.
public struct ClipList: Sendable, Hashable, Identifiable {
    public var id: ListID
    public var name: String
    public var type: ListType
    public var attributes: ListAttributes
    /// Position among the user's lists.
    public var index: Int
    public var isShared: Bool

    public init(id: ListID, name: String, type: ListType, attributes: ListAttributes, index: Int, isShared: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.attributes = attributes
        self.index = index
        self.isShared = isShared
    }
}
