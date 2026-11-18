/// The names of the index attributes an item is found by, as they are written in a query.
///
/// Everything an item is found by lives in attributes of Pasto's own that are searched only when
/// a query names them (`CSCustomAttributeKey`, not searchable by default), and the item has no
/// title, text or display name of Core Spotlight's: the clipboard history is found by Pasto's
/// search and never by the system's (⌘Space, Siri). Matching on these attributes works as it
/// does on Core Spotlight's `title` and `textContent`: word prefixes in any order, whatever the
/// case and the diacritics.
enum SearchIndexAttribute {
    static let modificationDate = "contentModificationDate"

    /// The item's title, or the name of its type when it has none.
    static let title = "pastoTitle"
    /// The item's text, at most 5000 characters of it.
    static let text = "pastoText"
    static let application = "pastoApp"
    static let type = "pastoType"
    static let device = "pastoDevice"
    static let pinboard = "pastoPinboard"

    /// Where typed words are looked for.
    static let textKeys = [title, text]
}
