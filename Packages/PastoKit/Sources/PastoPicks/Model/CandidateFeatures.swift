import PastoCore

/// What the ranking knows about one candidate.
struct CandidateFeatures: Sendable, Hashable, Codable {
    var itemIdentifier: ItemID
    /// Position among the candidates: 0 is the newest.
    var recencyRank: Int
    /// How often the journal saw the item pasted.
    var pasteCount: Int
    var sourceAppBundleIdentifier: String?
    var itemType: ItemType
    var itemClass: ItemClass
    /// How often something from the item's application was pasted into the destination; 0 for
    /// an item that came from no known application. Optional in the record, though
    /// `features(of:history:destination:)` always fills it in.
    var pairPasteCount: Int?
    /// Whether the item's application is the one the last paste into the destination came
    /// from; false while nothing has been pasted there. Optional in the record, though
    /// `features(of:history:destination:)` always fills it in.
    var isSourceOfLatestPaste: Bool?
}
