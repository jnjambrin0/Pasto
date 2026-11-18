import PastoCore

/// What a filter narrows the search by. The raw value is the type's name in text (`app:Mail`).
public enum SearchFilterType: String, Sendable, Hashable, CaseIterable {
    case app
    case type
    case title
    case date
    case device
    case pinboard
}

/// One condition of a query. What `value` holds depends on the type: the name of an
/// application or device, the name of an item type (`ItemType.searchName`), a pinboard's
/// identifier, a date range (`SearchDateRange.filterValue`) or free text for a title.
public struct SearchFilter: Sendable, Hashable {
    public var type: SearchFilterType
    public var value: String

    public init(type: SearchFilterType, value: String) {
        self.type = type
        self.value = value
    }
}

extension ItemType {
    /// How the type is called in filters and in the index. Fixed, not localized.
    public var searchName: String {
        switch self {
        case .unknown: "Unknown"
        case .image: "Image"
        case .color: "Color"
        case .files: "File"
        case .link: "Link"
        case .text: "Text"
        }
    }
}
