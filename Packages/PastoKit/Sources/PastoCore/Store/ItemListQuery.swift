import CoreData

/// Which items belong to a list and in which order.
///
/// Two independent attributes place an item. It is in the clipboard history while it has a
/// `timestamp`, and on a pinboard while `list` points to it — one pinboard at most. It can be
/// in both at once; an item in neither does not exist: the operations that take an item out of
/// its last place delete it.
enum ItemListQuery {
    /// The items `list` shows.
    static func predicate(for list: ListID) -> NSPredicate {
        list == .clipboard ? inHistory : NSPredicate(format: "list.identifier == %@", list.rawValue)
    }

    /// The history does not look at `list`: a pinned item stays in it.
    static var inHistory: NSPredicate {
        NSPredicate(format: "timestamp != nil")
    }

    /// What retention may let expire: pinned items never do.
    static var onNoPinboard: NSPredicate {
        NSPredicate(format: "list == nil")
    }

    /// Items last used before `date` that may expire: what a capacity deletes.
    static func expiring(before date: Date) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            onNoPinboard,
            NSPredicate(format: "timestamp < %@", date as NSDate),
        ])
    }

    /// The history newest first; a pinboard in the user's order, then newest first. Items that
    /// tie — out of the history, or stamped by a clock that did not move — go by identifier,
    /// so that the order is the same however it is computed (`ItemSortKey`). Descending, like the
    /// date: the history is then exactly the `byTimestamp` index read backwards (`PastoModelV2`).
    static func sortDescriptors(for list: ListID) -> [NSSortDescriptor] {
        let newestFirst = NSSortDescriptor(key: "timestamp", ascending: false)
        let byIdentifier = NSSortDescriptor(key: "identifier", ascending: false)
        if list == .clipboard {
            return [newestFirst, byIdentifier]
        }
        return [NSSortDescriptor(key: "displayOrderInPinboard", ascending: true), newestFirst, byIdentifier]
    }

    /// Whether `list` is ordered by position on a pinboard before the date.
    static func ordersByPosition(_ list: ListID) -> Bool {
        list != .clipboard
    }
}
