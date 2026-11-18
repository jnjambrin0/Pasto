import Foundation

/// What confirming the title field does.
nonisolated enum TitleEdit: Equatable {
    case unchanged
    /// `nil` removes the item's own title, which brings the type's name back.
    case set(String?)

    init(text: String, currentTitle: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self = trimmed == (currentTitle ?? "") ? .unchanged : .set(trimmed.isEmpty ? nil : trimmed)
    }
}
