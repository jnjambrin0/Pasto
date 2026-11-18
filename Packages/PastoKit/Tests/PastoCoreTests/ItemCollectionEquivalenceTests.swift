import CoreData
import Foundation
import os
@testable import PastoCore
import PastoFoundation
import Testing

/// `ItemCollection` follows the store by reading its history; the reference collection follows
/// it with a fetched results controller. Under random sequences of every kind of write, both
/// publish the same lists and report the same items as updated.
@MainActor
@Suite(.timeLimit(.minutes(2)))
struct ItemCollectionEquivalenceTests {
    /// One collection under test and its reference, with what each published since the last check.
    @MainActor
    private final class Pair {
        let name: String
        let current: ItemCollection
        let reference: FetchedResultsCollection
        var currentUpdates: Set<ItemID> = []
        var referenceUpdates: Set<ItemID> = []

        init(name: String, current: ItemCollection, reference: FetchedResultsCollection) {
            self.name = name
            self.current = current
            self.reference = reference
            current.onChange = { [unowned self] in currentUpdates.formUnion($0.updatedIDs) }
            reference.onChange = { [unowned self] in referenceUpdates.formUnion($0.updatedIDs) }
        }
    }

    /// A writer whose clock moves a second per transaction, so no two items ever tie.
    private final class Clock: Sendable {
        private let seconds = OSAllocatedUnfairLock(initialState: 10_000.0)
        var now: @Sendable () -> Date {
            { [seconds] in seconds.withLock { $0 += 1; return Date(timeIntervalSinceReferenceDate: $0) } }
        }
        func peek() -> Date { seconds.withLock { Date(timeIntervalSinceReferenceDate: $0) } }
    }

    @Test(arguments: [1, 2, 3, 4, 5] as [UInt64])
    func randomWritesPublishTheSameAsTheFetchedResultsController(seed: UInt64) async throws {
        let stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        let reader = StoreReader(stack: stack)
        let clock = Clock()
        let writer = StoreWriter(stack: stack, now: clock.now)
        var random = SeededRandom(seed: seed)
        let context = stack.container.viewContext

        // A store with some history and two pinboards, and a list nobody shows that marks
        // when the view context has caught up.
        let initial = try await writer.perform(author: .capture) { context in
            try (0..<30).map { try context.record(.text("seed \($0)", at: 5_000 + Double($0))).id }
        }
        let (work, home, barrier) = try await writer.perform(author: .user) { context in
            let work = try context.createPinboard(name: "Work", color: .blue)
            let home = try context.createPinboard(name: "Home", color: .red)
            try context.pin(Array(initial.prefix(6)), to: work)
            try context.pin(Array(initial.suffix(4)), to: home)
            return (work, home, try context.createPinboard(name: "Barrier", color: .gray))
        }
        let barrierObject = try #require(try context.fetch(ListEntity.makeRequest(NSPredicate(format: "identifier == %@", barrier.rawValue))).first)
        let searched = Array(initial.shuffled(using: &random).prefix(12))

        let newestFirst = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let pinboardOrder = [NSSortDescriptor(key: "displayOrderInPinboard", ascending: true)] + newestFirst
        let pairs = [
            Pair(name: "history", current: reader.itemCollection(for: .clipboard),
                 reference: FetchedResultsCollection(predicate: ItemListQuery.inHistory, sortDescriptors: newestFirst, context: context)),
            Pair(name: "work", current: reader.itemCollection(for: work),
                 reference: FetchedResultsCollection(predicate: ItemListQuery.predicate(for: work), sortDescriptors: pinboardOrder, context: context)),
            Pair(name: "search", current: reader.itemCollection(among: searched),
                 reference: FetchedResultsCollection(predicate: NSPredicate(format: "identifier IN %@", searched.map(\.rawValue)),
                                                     sortDescriptors: newestFirst, context: context)),
        ]

        let (merges, continuation) = AsyncStream.makeStream(of: Set<NSManagedObjectID>.self)
        let observer = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didMergeChangesObjectIDsNotification, object: context, queue: nil
        ) { notification in
            continuation.yield(notification.userInfo?[NSUpdatedObjectIDsKey] as? Set<NSManagedObjectID> ?? [])
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        var mergeIterator = merges.makeAsyncIterator()

        var pending: ItemChangeReversal?
        for step in 0..<150 {
            let items = try await writer.perform(author: .maintenance) { context in
                try context.context.fetch(ItemEntity.makeRequest()).map { ItemID(rawValue: $0.identifier) }
            }
            func some(_ count: Int) -> [ItemID] { Array(items.shuffled(using: &random).prefix(count)) }
            let now = clock.peek()
            let operation = Int(random.next() % 16)
            switch operation {
            case 0, 1:
                _ = try await writer.perform(author: .capture) { try $0.record(.text("new \(step)", at: now.timeIntervalSinceReferenceDate)) }
            case 2:
                if let item = some(1).first, let text = reader.item(item).map({ "\($0.id.rawValue)" }) {
                    // Copied again: the same content moves to the front.
                    _ = try await writer.perform(author: .capture) { context in
                        let checksum = try context.item(item).checksum
                        _ = try context.record(NewItem(type: .text, checksum: checksum, preview: .text(TextPreview(text: text, characterCount: 1)),
                                                       pasteboardItems: [], timestamp: now))
                    }
                }
            case 3:
                let doomed = some(Int(random.next() % 3) + 1)
                pending = try await writer.performReversibly(author: .user) { try $0.delete(doomed) }.reversal
            case 4:
                let removed = some(1)
                pending = try await writer.performReversibly(author: .user) { try $0.remove(removed, from: .clipboard) }.reversal
            case 5:
                if let item = some(1).first {
                    try await writer.perform(author: .user) { try $0.setTitle("title \(step)", of: item) }
                }
            case 6:
                let pinned = some(Int(random.next() % 3) + 1)
                let board = random.next() % 2 == 0 ? work : home
                pending = try await writer.performReversibly(author: .user) { try $0.pin(pinned, to: board) }.reversal
            case 7:
                let unpinned = some(1)
                pending = try await writer.performReversibly(author: .user) { try $0.unpin(unpinned) }.reversal
            case 8:
                let moved = some(2)
                let index = Int(random.next() % 4)
                try await writer.perform(author: .user) { try $0.moveItems(moved, toIndex: index, in: work) }
            case 9:
                if let item = some(1).first {
                    _ = try await writer.perform(author: .user) { try $0.duplicate(item) }
                }
            case 10:
                if let item = some(1).first {
                    try await writer.perform(author: .user) { try $0.touch(item, at: now) }
                }
            case 11:
                let cutoff = now.addingTimeInterval(-Double(random.next() % 200))
                _ = try await writer.perform(author: .maintenance) { try $0.deleteHistory(olderThan: cutoff) }
            case 12:
                if let reversal = pending {
                    // Undo: deleted items come back under their identifiers, as new objects.
                    pending = try await writer.performReversibly(author: .user) { try $0.apply(reversal) }.reversal
                }
            case 13:
                if let item = some(1).first {
                    try await writer.perform(author: .user) { try $0.replaceContent(of: item, with: .text("edited \(step)", at: 1)) }
                }
            case 14:
                if random.next() % 6 == 0 {
                    _ = try await writer.perform(author: .user) { try $0.eraseHistory() }
                }
            default:
                // Restoring: a reading of the clock per item, as with the real one.
                let ids = some(2)
                let tick = clock.now
                _ = try await writer.perform(author: .user) { context in
                    try context.moveToFrontOfHistory(ids, clock: tick)
                }
            }

            // The barrier's merge comes after every merge of the write.
            try await writer.perform(author: .user) { try $0.renameList(barrier, to: "Barrier \(step)") }
            while let updated = await mergeIterator.next(), !updated.contains(barrierObject.objectID) {}

            for pair in pairs {
                // The reference publishes during the merge; the collection, once it has read
                // the history off the main thread.
                await pair.current.settle()
                // Items that tie — out of the history and searched, or put back on a pinboard
                // where another one took their place — have no defined order in the reference;
                // the collection puts them in identifier order.
                let reference = canonicalOrder(pair.reference.snapshot.ids, byPosition: pair.name == "work", reader: reader)
                #expect(pair.current.snapshot.ids == reference, "\(pair.name) after step \(step) (operation \(operation))")
                #expect(pair.currentUpdates == pair.referenceUpdates, "\(pair.name) updates after step \(step) (operation \(operation))")
                pair.currentUpdates = []
                pair.referenceUpdates = []
            }
        }
        withExtendedLifetime(barrierObject) {}
    }

    /// `ids` — in the reference's order, which only sorts by key — with the items whose keys tie
    /// put in identifier order. A stable sort leaves everything else where it was.
    private func canonicalOrder(_ ids: [ItemID], byPosition: Bool, reader: StoreReader) -> [ItemID] {
        let keys = Dictionary(uniqueKeysWithValues: reader.items(ids).map { item in
            (item.id, ItemSortKey(order: byPosition ? item.displayOrderInPinboard : 0, timestamp: item.timestamp))
        })
        let ordered = ids.enumerated().sorted { first, second in
            let (firstKey, secondKey) = (keys[first.element]!, keys[second.element]!)
            if firstKey == secondKey, first.element != second.element {
                return second.element.rawValue.utf8.lexicographicallyPrecedes(first.element.rawValue.utf8)
            }
            return first.offset < second.offset
        }
        return ordered.map(\.element)
    }
}

/// A small seedable generator, so that a failing sequence can be replayed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
