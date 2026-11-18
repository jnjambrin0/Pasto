import PastoCore

/// What the store's history says happened to items, reduced to what the index has to do about
/// each one. An item is in one set at most.
struct SearchIndexChanges: Equatable, Sendable {
    private(set) var inserted: Set<ItemID> = []
    private(set) var updated: Set<ItemID> = []
    private(set) var deleted: Set<ItemID> = []

    init() {}

    init(_ transactions: [HistoryTransaction]) {
        for change in transactions.flatMap(\.changes) {
            record(change.kind, of: change.id)
        }
    }

    var isEmpty: Bool {
        inserted.isEmpty && updated.isEmpty && deleted.isEmpty
    }

    /// Adds changes that happened after these.
    mutating func merge(_ later: SearchIndexChanges) {
        later.inserted.forEach { record(.inserted, of: $0) }
        later.updated.forEach { record(.updated, of: $0) }
        later.deleted.forEach { record(.deleted, of: $0) }
    }

    private mutating func record(_ kind: HistoryTransaction.ItemChange.Kind, of id: ItemID) {
        switch kind {
        case .inserted:
            inserted.insert(id)
            updated.remove(id)
            deleted.remove(id)
        case .updated:
            // An item that is new to the index stays new, however often it changed since.
            if !inserted.contains(id) {
                updated.insert(id)
            }
            deleted.remove(id)
        case .deleted:
            deleted.insert(id)
            inserted.remove(id)
            updated.remove(id)
        }
    }
}
