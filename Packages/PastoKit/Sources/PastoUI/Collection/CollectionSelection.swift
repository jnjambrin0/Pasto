import Foundation

/// The selection state of a collection and the rules that change it.
///
/// `indexes` keeps the order in which cells were selected; the last one is the cursor that
/// arrow keys move from and that the view scrolls to.
public nonisolated struct CollectionSelection: Sendable, Equatable {
    public enum Mode: Sendable {
        /// Replace the selection with one cell (plain click, arrow keys).
        case single
        /// Add or remove one cell (⌘-click).
        case toggle
        /// Select from the range anchor to the cell (⇧-click, ⇧-arrows).
        case range
    }

    public private(set) var indexes: [Int] = []
    /// Where range selections start.
    public private(set) var rangeStart: Int?

    public init() {}

    public var isEmpty: Bool { indexes.isEmpty }
    public var cursor: Int? { indexes.last }

    public func contains(_ index: Int) -> Bool {
        indexes.contains(index)
    }

    public mutating func select(_ index: Int, mode: Mode, cellCount: Int) {
        guard (0..<cellCount).contains(index) else { return }
        switch mode {
        case .single:
            indexes = [index]
            rangeStart = index

        case .toggle:
            if let position = indexes.firstIndex(of: index) {
                // The last selected cell cannot be toggled off.
                guard indexes.count > 1 else { return }
                indexes.remove(at: position)
                rangeStart = indexes.last
            } else {
                indexes.append(index)
                rangeStart = index
            }

        case .range:
            guard let anchor = rangeStart else { return }
            let span = min(anchor, index)...max(anchor, index)
            // Runs that share a cell with the new span are replaced by it; unrelated runs (from
            // earlier ⌘-clicks) stay selected, ahead of the span.
            let kept = Self.runs(of: indexes).filter { run in !run.contains(where: span.contains) }.flatMap { $0 }
            let ordered = anchor <= index ? Array(span) : Array(span.reversed())
            indexes = kept + ordered
        }
    }

    public mutating func selectAll(cellCount: Int) {
        indexes = Array(0..<cellCount)
        rangeStart = indexes.last
    }

    /// State after a full reload: the first cell, if there is one.
    public mutating func reset(cellCount: Int) {
        indexes = cellCount > 0 ? [0] : []
        rangeStart = cellCount > 0 ? 0 : nil
    }

    /// Carries the selection across a content change. `newIndex` maps an old index to its new
    /// position, or nil when the cell was removed. An emptied selection falls back to the first
    /// cell, and range selections start again from the last selected cell.
    public mutating func remap(cellCount: Int, _ newIndex: (Int) -> Int?) {
        indexes = indexes.compactMap(newIndex)
        rangeStart = indexes.last
        if indexes.isEmpty { reset(cellCount: cellCount) }
    }

    /// Splits a selection, in the order it was made, into runs of neighbouring cells: two
    /// cells selected one after the other belong to the same run when they are adjacent, in
    /// either direction.
    private static func runs(of indexes: [Int]) -> [[Int]] {
        var runs: [[Int]] = []
        for index in indexes {
            if let previous = runs.last?.last, abs(previous - index) == 1 {
                runs[runs.count - 1].append(index)
            } else {
                runs.append([index])
            }
        }
        return runs
    }
}
