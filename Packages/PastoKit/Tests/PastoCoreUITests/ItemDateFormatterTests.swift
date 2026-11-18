import Foundation
import Testing
@testable import PastoCoreUI

/// The date a card shows, against a fixed clock.
@Suite struct ItemDateFormatterTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    let formatter = ItemDateFormatter(
        locale: Locale(identifier: "en_US"), calendar: Self.calendar, strings: CardStrings(languageCode: "en")!
    )

    func relative(secondsAgo: TimeInterval) -> String {
        formatter.relativeString(for: Self.now.addingTimeInterval(-secondsAgo), now: Self.now)
    }

    func abbreviated(secondsAgo: TimeInterval) -> String {
        formatter.abbreviatedString(for: Self.now.addingTimeInterval(-secondsAgo), now: Self.now)
    }

    @Test func whatTheSystemCallsNowReadsJustNow() {
        #expect(relative(secondsAgo: 0) == "just now")
        #expect(relative(secondsAgo: 0.2) == "just now")
    }

    @Test func olderItemsUseTheSystemsRelativeDate() {
        #expect(relative(secondsAgo: 30) == "30 seconds ago")
        #expect(relative(secondsAgo: 60) == "1 minute ago")
        #expect(relative(secondsAgo: 12 * 60) == "12 minutes ago")
        #expect(relative(secondsAgo: 3 * 3600) == "3 hours ago")
        #expect(relative(secondsAgo: 24 * 3600) == "yesterday")
    }

    @Test func justNowIsLocalized() {
        let spanish = ItemDateFormatter(
            locale: Locale(identifier: "es_ES"), calendar: Self.calendar, strings: CardStrings(languageCode: "es")!
        )
        #expect(spanish.relativeString(for: Self.now, now: Self.now) == "ahora mismo")
        #expect(spanish.relativeString(for: Self.now.addingTimeInterval(-120), now: Self.now) == "hace 2 minutos")
    }

    @Test func abbreviatedFormKeepsTheLargestWholeUnit() {
        #expect(abbreviated(secondsAgo: 5) == "5s")
        #expect(abbreviated(secondsAgo: 2 * 60) == "2m")
        #expect(abbreviated(secondsAgo: 2 * 60 + 59) == "2m")
        #expect(abbreviated(secondsAgo: 3 * 3600 + 40 * 60) == "3h")
        #expect(abbreviated(secondsAgo: 5 * 24 * 3600 + 3600) == "5d")
        #expect(abbreviated(secondsAgo: 40 * 24 * 3600) == "1mo")
        #expect(abbreviated(secondsAgo: 800 * 24 * 3600) == "2y")
    }

    /// Under a second there is no unit to show: the system's relative date is used as it is,
    /// without the "just now" substitution of the long form.
    @Test func abbreviatedFormOfABrandNewItemIsTheSystemsNow() {
        #expect(abbreviated(secondsAgo: 0) == "now")
        #expect(abbreviated(secondsAgo: 0.4) == "now")
    }

    @Test func tooltipIsTheAbsoluteDate() {
        // 2026-05-09 06:13:20 UTC
        let text = formatter.absoluteString(for: Self.now)
        #expect(text.contains("May 9, 2026"))
        #expect(text.contains("6:13"))
    }
}
