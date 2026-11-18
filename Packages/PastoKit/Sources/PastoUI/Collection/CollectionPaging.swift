import CoreGraphics

/// Page Up and Page Down in a collection: the selection moves by as many cells as fit whole in
/// view, and stops at either end.
nonisolated enum CollectionPaging {
    /// The cells that fit whole in `visibleWidth`, with `spacing` between them; at least one.
    static func cellsPerPage(visibleWidth: CGFloat, cellSide: CGFloat, spacing: CGFloat) -> Int {
        let stride = cellSide + spacing
        guard stride > 0 else { return 1 }
        return max(1, Int(((visibleWidth + spacing) / stride).rounded(.down)))
    }

    static func index(from cursor: Int, movingBy offset: Int, cellCount: Int) -> Int {
        min(max(cursor + offset, 0), max(cellCount - 1, 0))
    }
}
