/// What kind of content an item holds. The raw values are persisted: never renumber them.
public enum ItemType: Int64, Sendable, CaseIterable, Codable {
    case unknown = 0
    case image
    case color
    case files
    case link
    case text
}
