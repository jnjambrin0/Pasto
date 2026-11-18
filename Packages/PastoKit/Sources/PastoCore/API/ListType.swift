/// The clipboard history or a user-made pinboard. The raw values are persisted: never renumber them.
public enum ListType: Int64, Sendable, Codable {
    case clipboard = 0
    case pinboard
}
