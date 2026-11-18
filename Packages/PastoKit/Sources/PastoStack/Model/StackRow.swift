import Foundation
import PastoCore

/// One entry of the stack: an identity of its own plus the history item it stands for. The stack
/// copies no content, and the same item may sit in several rows.
struct StackRow: Identifiable, Equatable {
    let id: UUID
    var item: Item
}

/// Where a row was when it left the stack, which is what "Undo" needs to put it back.
struct StackRowPlace: Equatable {
    var row: StackRow
    /// The row that sat right above it; `nil` for the first row.
    var rowAboveID: StackRow.ID?
    var index: Int
}
