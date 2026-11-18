import PastoCore

/// Where the suggestions that depend on the user's history come from. Item types and date
/// presets are fixed lists and need no source.
@MainActor
public protocol SearchSuggestionDataSource {
    /// The names of the applications some item was copied from, in ascending order.
    func applicationNames() -> [String]
    /// The names of the devices some item was copied on, in ascending order.
    func deviceNames() -> [String]
    /// The pinboards, by name in ascending order.
    func pinboards() -> [SearchSuggestionPinboard]
}

public struct SearchSuggestionPinboard: Sendable, Hashable {
    public var id: ListID
    public var name: String

    public init(id: ListID, name: String) {
        self.id = id
        self.name = name
    }
}

/// The suggestions of the user's store.
@MainActor
public struct StoreSuggestionDataSource: SearchSuggestionDataSource {
    private let reader: StoreReader

    public init(reader: StoreReader) {
        self.reader = reader
    }

    public func applicationNames() -> [String] {
        reader.sourceApplicationNames()
    }

    public func deviceNames() -> [String] {
        reader.deviceNames()
    }

    public func pinboards() -> [SearchSuggestionPinboard] {
        reader.lists()
            .filter { $0.type == .pinboard }
            .map { SearchSuggestionPinboard(id: $0.id, name: $0.name) }
            .sorted { $0.name < $1.name }
    }
}
