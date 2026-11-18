import PastoFoundation

/// Decides how a collection view should go from the content it shows to a new snapshot.
///
/// Inlinable, like the difference it computes, so that it is specialised for the identifiers of
/// the module that uses it: generic code that compares a few hundred thousand identifiers through
/// a protocol witness costs the main thread milliseconds.
public nonisolated struct SnapshotApplier<ID: Hashable & Sendable>: Sendable {
    public enum Application: Sendable, Equatable {
        /// The snapshot matches what is shown.
        case none
        /// Too different (or nothing shown yet) to animate: reload everything.
        case reload
        case changes(CollectionChangeset)
    }

    /// Above this many deletions, insertions and moves the collection reloads instead of animating.
    @inlinable public static var batchUpdateLimit: Int { 300 }

    /// The content shown, as last applied.
    public var snapshot: CollectionSnapshot<ID>? { shown }

    @usableFromInline var shown: CollectionSnapshot<ID>?

    public init() {}

    /// The identifiers currently shown, in order.
    public var ids: [ID] { snapshot?.ids ?? [] }

    /// Records `new` as the content shown and returns how to get there.
    @inlinable public mutating func apply(_ new: CollectionSnapshot<ID>) -> Application {
        guard let old = shown else {
            shown = new
            return .reload
        }
        shown = new

        // More than the limit is a reload however much more it is: the difference stops there.
        guard let changes = CollectionChanges.between(old, new, changeLimit: Self.batchUpdateLimit) else {
            return .reload
        }
        if changes.isEmpty { return .none }
        return .changes(CollectionChangeset(
            deletions: changes.removals.map(\.index),
            insertions: changes.insertions.map(\.index),
            moves: changes.moves.map { .init(from: $0.from, to: $0.to) },
            // Looked up from the front, where updated cards usually are, rather than by indexing
            // the whole snapshot.
            updates: changes.updates.isEmpty ? [] : new.indexes(of: Set(changes.updates))
        ))
    }
}
