// Differences between large snapshots. A history of hundreds of thousands of items changes by one
// capture, one deletion or one re-copy at a time; hashing every element of both snapshots to find
// that costs the main thread tens of milliseconds. These shortcuts find it by walking the snapshots
// instead, and give way to the general algorithm when the change turns out not to be small.

extension CollectionChanges {
    /// The most insertions plus removals (a move counts as one of each) the bounded edit-script
    /// search looks for when no change limit is given. Measured on 300 000 identifiers: ten items
    /// moved take 0.3 ms, and a search that gives up adds some 15 ms to the general algorithm's 180.
    @inlinable static var editScriptLimit: Int { 32 }

    /// - Parameter changeLimit: With a limit, a difference of more removals, insertions and moves
    ///   than it is `nil` as soon as that is known, instead of being worked out: the edit-script
    ///   search goes as far as twice the limit (a change of at most `limit` has at most that many
    ///   edits, a move being two) and the general algorithm never runs.
    @inlinable static func largeDifference(_ old: [ID], _ new: [ID], changeLimit: Int? = nil) -> CollectionChanges<ID>? {
        // The ends both snapshots share stay where they are: some longest common subsequence
        // always includes them, so the moves found in what is left are still the fewest.
        let shorter = min(old.count, new.count)
        var prefix = 0
        while prefix < shorter, old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        let oldMiddle = old[prefix..<(old.count - suffix)]
        let newMiddle = new[prefix..<(new.count - suffix)]

        // Removals minus insertions is the difference in length: more than the limit of either
        // alone is more than the limit together.
        if let changeLimit, abs(oldMiddle.count - newMiddle.count) > changeLimit {
            return nil
        }
        if newMiddle.isEmpty {
            return CollectionChanges(removals: oldMiddle.indices.reversed().map { Removal(id: old[$0], index: $0) })
        }
        if oldMiddle.isEmpty {
            return CollectionChanges(insertions: newMiddle.indices.map { Insertion(id: new[$0], index: $0) })
        }
        if oldMiddle.count + newMiddle.count <= largeCollectionThreshold {
            return difference(oldMiddle, newMiddle)
        }
        if newMiddle.count < oldMiddle.count, let removals = removalsOnly(from: oldMiddle, to: newMiddle) {
            return CollectionChanges(removals: removals)
        }
        if oldMiddle.count < newMiddle.count, let insertions = removalsOnly(from: newMiddle, to: oldMiddle) {
            return CollectionChanges(insertions: insertions.reversed().map { Insertion(id: $0.id, index: $0.index) })
        }
        guard let changeLimit else {
            return shortEditScript(from: oldMiddle, to: newMiddle, limit: editScriptLimit) ?? difference(oldMiddle, newMiddle)
        }
        return shortEditScript(from: oldMiddle, to: newMiddle, limit: 2 * changeLimit)
    }

    /// The elements of `longer` that are not in `shorter`, by descending index, when `shorter` is
    /// `longer` without them and nothing else changed; `nil` otherwise. One pass, no hashing.
    ///
    /// With unique identifiers, an element left unmatched by the greedy walk cannot appear later
    /// in `shorter`: everything there matched an element of `longer`, and none matched twice.
    @inlinable static func removalsOnly(from longer: ArraySlice<ID>, to shorter: ArraySlice<ID>) -> [Removal]? {
        let expected = longer.count - shorter.count
        var removals: [Removal] = []
        removals.reserveCapacity(expected)
        var next = shorter.startIndex
        for index in longer.indices {
            if next < shorter.endIndex, longer[index] == shorter[next] {
                next += 1
            } else {
                removals.append(Removal(id: longer[index], index: index))
                if removals.count > expected { return nil }
            }
        }
        guard next == shorter.endIndex else { return nil }
        return removals.reversed()
    }

    /// The shortest edit script from `old` to `new` (Myers' O(ND) algorithm), turned into
    /// removals, insertions and moves; `nil` when it needs more than `limit` edits.
    ///
    /// The diagonals the script keeps are a longest common subsequence, so the survivors outside
    /// it — removed and inserted again — are the fewest moves.
    ///
    /// With identifiers that appear once, an element only matches on one diagonal, and a diagonal
    /// is only ever walked forward: the search costs the length of the snapshots plus the square
    /// of the edits, whether it finds the script or gives up (300 000 identifiers, 600 edits: a
    /// few milliseconds).
    @inlinable static func shortEditScript(from old: ArraySlice<ID>, to new: ArraySlice<ID>, limit: Int) -> CollectionChanges<ID>? {
        let (n, m) = (old.count, new.count)
        let offset = limit + 1
        // furthest[offset + k]: how far along `old` the furthest path on diagonal k reaches.
        var furthest = [Int](repeating: 0, count: 2 * limit + 3)
        // Before step d, the diagonals -d...d of `furthest`, from index d * d: what walking the
        // path back needs.
        var trace: [Int] = []

        for edits in 0...limit {
            trace.append(contentsOf: furthest[(offset - edits)...(offset + edits)])
            for diagonal in stride(from: -edits, through: edits, by: 2) {
                let goesDown = diagonal == -edits
                    || (diagonal != edits && furthest[offset + diagonal - 1] < furthest[offset + diagonal + 1])
                var x = goesDown ? furthest[offset + diagonal + 1] : furthest[offset + diagonal - 1] + 1
                var y = x - diagonal
                while x < n, y < m, old[old.startIndex + x] == new[new.startIndex + y] {
                    x += 1
                    y += 1
                }
                furthest[offset + diagonal] = x
                if x >= n, y >= m {
                    return script(trace: trace, edits: edits, old: old, new: new)
                }
            }
        }
        return nil
    }

    /// Walks the path found back from the end, collecting what each edit removed or inserted.
    @inlinable static func script(
        trace: [Int],
        edits: Int,
        old: ArraySlice<ID>,
        new: ArraySlice<ID>
    ) -> CollectionChanges<ID> {
        var x = old.count
        var y = new.count
        var removed: [Int] = []
        var inserted: [Int] = []
        for step in stride(from: edits, to: 0, by: -1) {
            // How far diagonal k reached before this step.
            let furthest = { (diagonal: Int) in trace[step * step + step + diagonal] }
            let diagonal = x - y
            let cameDown = diagonal == -step
                || (diagonal != step && furthest(diagonal - 1) < furthest(diagonal + 1))
            let previousDiagonal = cameDown ? diagonal + 1 : diagonal - 1
            let previousX = furthest(previousDiagonal)
            let previousY = previousX - previousDiagonal
            if cameDown {
                inserted.append(new.startIndex + previousY)
            } else {
                removed.append(old.startIndex + previousX)
            }
            x = previousX
            y = previousY
        }

        // An element removed and inserted again is a move. Removals and insertions are paired one
        // to one, so that a repeated identifier — which a snapshot must not hold, but may — still
        // gives changes that turn one snapshot into the other.
        var insertedIndexesByID: [ID: [Int]] = [:]
        for index in inserted.sorted() {
            insertedIndexesByID[new[index], default: []].append(index)
        }
        var changes = CollectionChanges()
        var movedDestinations: Set<Int> = []
        for index in removed.sorted(by: >) {
            let id = old[index]
            if let destination = insertedIndexesByID[id]?.popLast() {
                changes.moves.append(Move(id: id, from: index, to: destination))
                movedDestinations.insert(destination)
            } else {
                changes.removals.append(Removal(id: id, index: index))
            }
        }
        changes.insertions = inserted.sorted().compactMap { movedDestinations.contains($0) ? nil : Insertion(id: new[$0], index: $0) }
        changes.moves.sort { $0.to < $1.to }
        return changes
    }
}
