/// Keyboard navigation in the filter browser: every entry of every section has an index, counted
/// in reading order, and each section is a grid of its own.
nonisolated enum FilterBrowserNavigation {
    enum Direction {
        case up
        case down
        case left
        case right
    }

    /// The entry the highlight moves to.
    ///
    /// - Parameters:
    ///   - current: The highlighted entry; nil when there is none yet.
    ///   - sectionSizes: How many entries each section shows, buttons included.
    /// - Returns: Nil only when there are no entries.
    static func index(
        from current: Int?,
        moving direction: Direction,
        sectionSizes: [Int],
        columnCount: Int = SearchMetrics.Browser.columnCount
    ) -> Int? {
        let sizes = sectionSizes.filter { $0 > 0 }
        let total = sizes.reduce(0, +)
        guard total > 0 else { return nil }
        // The first move only brings the highlight in, whatever its direction.
        guard let current, (0..<total).contains(current) else { return 0 }

        // Left and right follow the reading order and wrap around the whole browser.
        switch direction {
        case .right: return (current + 1) % total
        case .left: return (current + total - 1) % total
        case .up, .down: break
        }

        var sectionStart = 0
        var section = 0
        while current >= sectionStart + sizes[section] {
            sectionStart += sizes[section]
            section += 1
        }
        let size = sizes[section]
        let position = current - sectionStart
        let column = position % columnCount

        if direction == .up {
            if position >= columnCount { return current - columnCount }
            // From a section's first row to the last row of the one before; from the very first
            // row, around to the last entry.
            guard section > 0 else { return total - 1 }
            let previousSize = sizes[section - 1]
            let lastRowStart = (previousSize - 1) / columnCount * columnCount
            return sectionStart - previousSize + lastRowStart + min(column, previousSize - lastRowStart - 1)
        }

        let isInLastRow = position / columnCount == (size - 1) / columnCount
        if !isInLastRow {
            // A shorter last row has no cell below: the section's last entry stands in for it.
            return sectionStart + min(position + columnCount, size - 1)
        }
        // From a section's last row to the first row of the next one; from the very last row,
        // around to the first entry.
        guard section < sizes.count - 1 else { return 0 }
        return sectionStart + size + min(column, sizes[section + 1] - 1)
    }
}
