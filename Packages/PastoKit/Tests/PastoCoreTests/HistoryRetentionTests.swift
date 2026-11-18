import Foundation
@testable import PastoCore
import Testing

/// The history's capacity is an age in days.
struct HistoryRetentionTests {
    private let now = Date.second(1_000 * 86_400)

    @Test(arguments: [(HistoryCapacity.day, 1), (.week, 7), (.month, 30), (.year, 365)])
    func theCutoffIsThatManyDaysBeforeNow(capacity: HistoryCapacity, days: Int) {
        #expect(HistoryRetention.cutoff(for: capacity, at: now) == .second(TimeInterval(1_000 - days) * 86_400))
    }

    @Test func anUnlimitedHistoryHasNoCutoff() {
        #expect(HistoryRetention.cutoff(for: .unlimited, at: now) == nil)
    }

    @Test func aCapacityBetweenTheNamedOnesIsItsNumberOfDays() {
        #expect(HistoryRetention.cutoff(for: HistoryCapacity(days: 14), at: now) == .second(986 * 86_400))
    }

    @Test func aCapacityIsStoredAsItsBareNumberOfDays() throws {
        let data = try BinaryPropertyList.encode(ListAttributes.clipboard(capacity: HistoryCapacity(days: 60)))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Int]]

        #expect(plist == ["clipboard": ["capacity": 60]])
        #expect(try BinaryPropertyList.decode(ListAttributes.self, from: data) == .clipboard(capacity: HistoryCapacity(days: 60)))
    }
}
