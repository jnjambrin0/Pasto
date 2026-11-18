import Foundation
@testable import PastoCore
import Testing

struct OrderedItemListTests {
    private typealias List = OrderedItemList<Int>

    private func member(_ handle: Int, time: Double?, order: Int64 = 0, id: String? = nil) -> List.Member {
        List.Member(
            handle: handle,
            id: ItemID(rawValue: id ?? String(format: "id-%05d", handle)),
            key: ItemSortKey(order: order, timestamp: time.map { Date(timeIntervalSinceReferenceDate: $0) })
        )
    }

    @Test func newestFirstThenWithoutADateLast() {
        let list = List([member(1, time: 10), member(2, time: nil), member(3, time: 30), member(4, time: 20)])

        #expect(list.ids.map(\.rawValue) == ["id-00003", "id-00004", "id-00001", "id-00002"])
    }

    @Test func positionFirstThenNewestFirstThenIdentifierDescending() {
        let list = List([
            member(1, time: 10, order: 1),
            member(2, time: 50, order: 0),
            member(3, time: 20, order: 1),
            member(4, time: nil, order: 0, id: "b"),
            member(5, time: nil, order: 0, id: "a"),
        ])

        #expect(list.ids.map(\.rawValue) == ["id-00002", "b", "a", "id-00003", "id-00001"])
    }

    @Test func oneInsertionAndOneRemovalLandInPlace() {
        var list = List((1...5).map { member($0, time: Double($0)) })

        list.insert([member(9, time: 3.5)])
        #expect(list.ids.map(\.rawValue) == ["id-00005", "id-00004", "id-00009", "id-00003", "id-00002", "id-00001"])

        let removedSome = list.remove([3, 42])
        let removedNone = list.remove([42])
        #expect(removedSome)
        #expect(!removedNone)
        #expect(list.ids.map(\.rawValue) == ["id-00005", "id-00004", "id-00009", "id-00002", "id-00001"])
        #expect(!list.contains(3))
        #expect(list.contains(9))
    }

    /// Random runs of insertions and removals, small and large, against sorting from scratch.
    @Test(arguments: [7, 8, 9] as [UInt64])
    func randomChangesMatchSortingAgain(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        var reference: [Int: List.Member] = [:]
        var next = 0
        func fresh() -> List.Member {
            next += 1
            // Few distinct dates and positions, so that ties are common.
            let time = random.next() % 5 == 0 ? nil : Double(random.next() % 40)
            return member(next, time: time, order: Int64(random.next() % 3), id: String(format: "%08x", random.next() % 0xFFFF_FFFF))
        }
        let initial = (0..<200).map { _ in fresh() }
        var list = List(initial.shuffled(using: &random))
        initial.forEach { reference[$0.handle] = $0 }

        for _ in 0..<300 {
            if random.next() % 2 == 0 || reference.isEmpty {
                let arriving = (0..<Int(random.next() % 20 + 1)).map { _ in fresh() }
                list.insert(arriving)
                arriving.forEach { reference[$0.handle] = $0 }
            } else {
                let leaving = reference.keys.shuffled(using: &random).prefix(Int(random.next() % 20 + 1))
                list.remove(Array(leaving) + [-1])
                leaving.forEach { reference[$0] = nil }
            }
            let expected = reference.values.sorted(by: List.precedes).map(\.id)
            #expect(list.ids == expected)
            #expect(list.count == reference.count)
        }
    }
}
