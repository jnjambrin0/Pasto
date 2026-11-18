/// The contents of a collection at one moment: which elements it has and in which order.
///
/// Data sources publish a new snapshot after every change; views animate from the previous one
/// with `CollectionChanges.between(_:_:)`.
public struct CollectionSnapshot<ID: Hashable & Sendable>: Sendable, Equatable {
    /// Presentation order. Identifiers must be unique.
    public var ids: [ID]
    /// Elements whose content changed since the previous snapshot.
    public var updatedIDs: Set<ID>

    public init(ids: [ID], updatedIDs: Set<ID> = []) {
        self.ids = ids
        self.updatedIDs = updatedIDs
    }

    /// The positions of the elements among `wanted` that the snapshot holds, ascending.
    ///
    /// Looks from the front and stops once it has found them all, so a few elements near the
    /// front — where captures and re-copies land — cost little however long the snapshot is.
    @inlinable public func indexes(of wanted: Set<ID>) -> [Int] {
        guard !wanted.isEmpty else { return [] }
        var found: [Int] = []
        // A handful is compared one by one: cheaper than hashing every element on the way.
        let few = wanted.count <= 4 ? Array(wanted) : nil
        for index in ids.indices where few?.contains(ids[index]) ?? wanted.contains(ids[index]) {
            found.append(index)
            if found.count == wanted.count { break }
        }
        return found
    }
}
