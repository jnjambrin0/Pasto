import Foundation

/// What confirming an edit of a card's title amounts to.
nonisolated enum TitleEdit: Equatable, Sendable {
    /// Nothing to write.
    case unchanged
    /// The item's new title; `nil` takes its title away, and the card shows its type's name again.
    case rename(String?)

    /// - Parameters:
    ///   - typed: The text in the field when the edit was confirmed.
    ///   - customTitle: The title the item has, if the user gave it one.
    ///   - typeName: What the card shows while the item has no title of its own.
    init(typed: String, customTitle: String?, typeName: String) {
        let ownTitle = customTitle.flatMap { $0.isEmpty ? nil : $0 }
        // Compared before trimming: a trailing space counts as a change, and ends up writing
        // the trimmed text.
        guard typed != ownTitle ?? typeName else {
            self = .unchanged
            return
        }
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            self = .rename(trimmed)
        } else if ownTitle != nil {
            self = .rename(nil)
        } else {
            // Blank over no title: the card would look the same either way.
            self = .unchanged
        }
    }
}
