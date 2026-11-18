@testable import PastoFoundation
import Testing

/// Above `largeCollectionThreshold` the difference takes shortcuts. Whatever it takes, the result
/// has to transform the old snapshot into the new one with the same removals and insertions and as
/// few moves as the general algorithm finds.
struct LargeCollectionChangesTests {
    private typealias Changes = CollectionChanges<Int>

    private let size = 5_000

    private func check(_ old: [Int], _ new: [Int], updated: Set<Int> = [], _ comment: Comment? = nil) {
        precondition(old.count + new.count > Changes.largeCollectionThreshold)
        let changes = Changes.between(CollectionSnapshot(ids: old), CollectionSnapshot(ids: new, updatedIDs: updated))
        let reference = Changes.difference(old[...], new[...])

        #expect(apply(changes, to: old) == new, comment)
        #expect(changes.removals == reference.removals, comment)
        #expect(changes.insertions == reference.insertions, comment)
        #expect(changes.moves.count == reference.moves.count, comment)
        #expect(changes.updates == new.filter { updated.contains($0) && old.contains($0) }, comment)
    }

    @Test func theChangesOfEveryDay() {
        let old = Array(0..<size)
        // A capture; a capture that lets the oldest item expire; a deletion; a re-copy.
        check(old, [-1] + old, updated: [-1])
        check(old, [-1] + old.dropLast())
        check(old, old.filter { $0 != 2_500 })
        check(old, [3_000] + old.filter { $0 != 3_000 }, updated: [3_000])
        // Something renamed deep in the list: nothing moves.
        check(old, old, updated: [4_321])
    }

    @Test func manyRemovalsOrManyInsertionsAlone() {
        var random = SystemRandomNumberGenerator()
        let old = Array(0..<size)
        let survivors = old.filter { _ in Int.random(in: 0..<10, using: &random) != 0 }
        check(old, survivors, "a tenth removed")
        check(survivors, old, "a tenth inserted")
        check(old, [], "everything removed")
        check([], old, "everything inserted")
    }

    @Test(arguments: 0..<40)
    func aFewMixedChanges(seed: Int) {
        var random = Seeded(seed: UInt64(seed))
        var new = Array(0..<size)
        let edits = Int(random.next() % 12)
        var next = size
        for _ in 0..<edits {
            switch random.next() % 3 {
            case 0:
                new.insert(next, at: Int(random.next() % UInt64(new.count + 1)))
                next += 1
            case 1:
                new.remove(at: Int(random.next() % UInt64(new.count)))
            default:
                let element = new.remove(at: Int(random.next() % UInt64(new.count)))
                new.insert(element, at: Int(random.next() % UInt64(new.count + 1)))
            }
        }
        let updated = Set((0..<3).map { _ in Int(random.next() % UInt64(next)) })
        check(Array(0..<size), new, updated: updated, "seed \(seed), \(edits) edits")
    }

    @Test func aShuffleFallsBackToTheGeneralAlgorithm() {
        var random = Seeded(seed: 99)
        let old = Array(0..<size)
        check(old, old.shuffled(using: &random))
    }

    /// With a change limit, a difference over the limit is `nil` without being worked out; one
    /// within it is the same as without a limit. So the collection view reloads or animates
    /// exactly as the whole difference would have it, from a single item to hundreds of mixed
    /// edits.
    @Test(arguments: 0..<60)
    func aLimitDecidesAsTheWholeDifferenceDoes(seed: Int) {
        var random = Seeded(seed: UInt64(1_000 + seed))
        let limit = 300
        let old = Array(0..<size)
        var new = old
        // Up to twice the limit, so that both sides of it are tried.
        let edits = Int(random.next() % UInt64(2 * limit))
        var next = size
        for _ in 0..<edits {
            switch random.next() % 4 {
            case 0:
                new.insert(next, at: Int(random.next() % UInt64(new.count + 1)))
                next += 1
            case 1:
                new.remove(at: Int(random.next() % UInt64(new.count)))
            default:
                let element = new.remove(at: Int(random.next() % UInt64(new.count)))
                new.insert(element, at: Int(random.next() % UInt64(new.count + 1)))
            }
        }
        let updated = Set((0..<3).map { _ in Int(random.next() % UInt64(next)) })
        let whole = Changes.difference(old[...], new[...])
        let wholeCount = whole.removals.count + whole.insertions.count + whole.moves.count
        let limited = Changes.between(CollectionSnapshot(ids: old), CollectionSnapshot(ids: new, updatedIDs: updated), changeLimit: limit)

        #expect((limited == nil) == (wholeCount > limit), "seed \(seed): \(edits) edits, \(wholeCount) changes")
        if let limited {
            #expect(apply(limited, to: old) == new)
            #expect(limited.removals == whole.removals)
            #expect(limited.insertions == whole.insertions)
            #expect(limited.moves.count == whole.moves.count)
            #expect(limited.updates == new.filter { updated.contains($0) && old.contains($0) })
        }
    }

    @Test func manyMovesWithinTheLimitAreWorkedOutWithoutTheGeneralAlgorithm() {
        let old = Array(0..<size)
        // 100 items brought to the front, as pasting a hundred of them does.
        let moved = stride(from: 40, to: size, by: 49).prefix(100).map { $0 }
        let new = moved + old.filter { !moved.contains($0) }
        let limited = Changes.largeDifference(old, new, changeLimit: 300)

        #expect(limited.map { apply($0, to: old) } == new)
        #expect(limited?.moves.count == 100)
        #expect(limited?.removals.isEmpty == true)
        // Over the limit: a difference in length alone is enough to know.
        #expect(Changes.largeDifference(old, Array(old.dropFirst(301)), changeLimit: 300) == nil)
        #expect(Changes.largeDifference(old, Array(old.dropFirst(300)), changeLimit: 300)?.removals.count == 300)
    }

    /// A snapshot must not hold an identifier twice, but one that does still gets changes that
    /// turn it into the next, through every path of a large difference.
    @Test func aRepeatedIdentifierStillGivesChangesThatApply() {
        var old = Array(0..<size)
        old[100] = 7
        // Moved to the front, twice over, with another element: the edit-script search.
        var moved = old
        moved.remove(at: 100)
        moved.remove(at: 7)
        moved.remove(at: 3_000)
        moved.insert(contentsOf: [7, 3_001, 7], at: 0)
        for limit in [nil, 300] as [Int?] {
            let changes = limit.map { Changes.between(CollectionSnapshot(ids: old), CollectionSnapshot(ids: moved), changeLimit: $0) }
                ?? Changes.between(CollectionSnapshot(ids: old), CollectionSnapshot(ids: moved))
            #expect(changes.map { apply($0, to: old) } == moved)
        }
        // Removals only.
        let removed = Array(old[200...])
        #expect(apply(Changes.between(CollectionSnapshot(ids: old), CollectionSnapshot(ids: removed)), to: old) == removed)
    }

    @Test func indexesOfAFewStopEarlyAndOfManyFindThemAll() {
        let snapshot = CollectionSnapshot(ids: Array(0..<size))
        #expect(snapshot.indexes(of: [3, 1]) == [1, 3])
        #expect(snapshot.indexes(of: [3, 1, -5]) == [1, 3])
        #expect(snapshot.indexes(of: Set(stride(from: 0, to: size, by: 7))) == Array(stride(from: 0, to: size, by: 7)))
        #expect(snapshot.indexes(of: []) == [])
    }

    // MARK: - Helpers

    private func apply(_ changes: Changes, to old: [Int]) -> [Int] {
        var ids = old
        let leaving = changes.removals.map(\.index) + changes.moves.map(\.from)
        for index in leaving.sorted(by: >) {
            ids.remove(at: index)
        }
        let arriving = changes.insertions.map { (index: $0.index, id: $0.id) } + changes.moves.map { (index: $0.to, id: $0.id) }
        for arrival in arriving.sorted(by: { $0.index < $1.index }) {
            ids.insert(arrival.id, at: arrival.index)
        }
        return ids
    }

    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }
}
