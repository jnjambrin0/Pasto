import Foundation
import PastoCore
@testable import PastoSearch
import Testing

struct SearchWindowTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000.75)
    private let day: TimeInterval = 24 * 3600

    @Test func theWindowsGrowFromTheLastDayToAllOfTime() {
        let whole = now.timeIntervalSince1970.rounded(.down)

        #expect(SearchWindow.sequence(endingAt: now) == [
            SearchWindow(start: Date(timeIntervalSince1970: whole - day)),
            SearchWindow(start: Date(timeIntervalSince1970: whole - 7 * day)),
            SearchWindow(start: Date(timeIntervalSince1970: whole - 30 * day)),
            SearchWindow(start: nil),
        ])
    }

    /// A window takes in every date of the smaller ones, the future included.
    @Test(arguments: [-400.0, -365, -200, -30, -29.5, -7, -1, -0.5, 0, 2])
    func eachWindowHoldsTheOnesBeforeIt(daysFromNow: Double) {
        let date = now.addingTimeInterval(daysFromNow * day)
        let windows = SearchWindow.sequence(endingAt: now)
        let first = windows.firstIndex { $0.contains(date) }
        #expect(first != nil)
        #expect(windows[(first ?? 0)...].allSatisfy { $0.contains(date) })
    }

    @Test func aWindowNarrowsTheQueryByDate() {
        let query = "(title = \"a*\"cwdt)"

        #expect(SearchWindow(start: Date(timeIntervalSince1970: 0)).restricting(query) == "((title = \"a*\"cwdt)) && contentModificationDate >= $time.iso(1970-01-01T00:00:00Z)")
        #expect(SearchWindow(start: nil).restricting(query) == query)
    }

    /// Asking window by window and stopping at the first that fills the limit gives the hits
    /// one query over all of time gives.
    @Test func searchingWindowByWindowFindsWhatOneQueryFinds() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let count = Int.random(in: 0...400, using: &generator)
            let items = (0..<count).map { index in
                (id: ItemID(rawValue: "item-\(index)"), date: now.addingTimeInterval(-Double.random(in: -2...500, using: &generator) * day))
            }
            let limit = Int.random(in: 1...120, using: &generator)

            var whole = NewestHits(limit: limit)
            for item in items.shuffled(using: &generator) { whole.insert(item.id, date: item.date) }

            var windowed = NewestHits(limit: limit)
            for window in SearchWindow.sequence(endingAt: now) {
                windowed = NewestHits(limit: limit)
                for item in items.shuffled(using: &generator) where window.contains(item.date) {
                    windowed.insert(item.id, date: item.date)
                }
                if windowed.isFull { break }
            }

            #expect(windowed.ids == whole.ids)
        }
    }
}

struct NewestHitsOrderTests {
    /// The quick rejection of a full list keeps exactly what sorting everything would.
    @Test func keepsTheNewestWhateverTheOrderTheyArriveIn() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let dates = (0..<300).map { _ in Date(timeIntervalSince1970: Double(Int.random(in: 0...50, using: &generator))) }
            let items = dates.enumerated().map { (id: ItemID(rawValue: String(format: "%03d", $0.offset)), date: $0.element) }
            let limit = Int.random(in: 1...100, using: &generator)

            var hits = NewestHits(limit: limit)
            for item in items.shuffled(using: &generator) { hits.insert(item.id, date: item.date) }

            let expected = items
                .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.rawValue > $1.id.rawValue }
                .prefix(limit)
                .map(\.id)
            #expect(hits.ids == expected)
            #expect(hits.isFull == (items.count >= limit))
        }
    }
}
