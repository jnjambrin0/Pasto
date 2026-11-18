import AppKit

/// How the drag of a row ended.
enum StackDragOutcome: Equatable {
    /// Nobody took the row.
    case cancelled
    /// The row was dropped back on the panel, after reordering the rows on its way.
    case droppedInPanel
    /// Another application, or another part of Pasto, took the row.
    case droppedOutside

    /// - Parameters:
    ///   - operation: What the destination did, as the dragging session reports it.
    ///   - didDropInPanel: Whether the panel itself took the drop.
    init(operation: NSDragOperation, didDropInPanel: Bool) {
        self = if operation.isEmpty {
            .cancelled
        } else if didDropInPanel {
            .droppedInPanel
        } else {
            .droppedOutside
        }
    }
}
