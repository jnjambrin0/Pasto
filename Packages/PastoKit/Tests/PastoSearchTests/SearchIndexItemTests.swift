import Foundation
import PastoCore
@testable import PastoSearch
import Testing

struct SearchIndexItemTextTests {
    private func item(text: String?) -> IndexableItem {
        IndexableItem(id: ItemID(rawValue: "a"), type: .text, text: text, timestamp: Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test func aLongTextKeepsItsFirstCharactersOnly() {
        let long = String(repeating: "palabra ñandú ", count: 100_000)
        let indexed = SearchIndexItem(item(text: long))

        #expect(indexed.text == String(long.prefix(SearchIndexItem.maxTextLength)))
    }

    /// The parts are cut before they are joined; the result is what cutting the joined whole gave.
    @Test func recognizedWordsFollowTheTextUpToTheSameLimit() {
        let short = SearchIndexItem(item(text: "hola"), recognizedText: "Total 42")
        #expect(short.text == "hola\nTotal 42")

        let text = String(repeating: "a", count: 4_990)
        let recognized = String(repeating: "b", count: 20_000)
        let joined = SearchIndexItem(item(text: text), recognizedText: recognized)
        #expect(joined.text == String((text + "\n" + recognized).prefix(SearchIndexItem.maxTextLength)))

        // A text that ends in a carriage return makes one character with the line break.
        let lines = String(repeating: "c", count: 4_998) + "\r"
        let crlf = SearchIndexItem(item(text: lines), recognizedText: "dd")
        #expect(crlf.text == String((lines + "\n" + "dd").prefix(SearchIndexItem.maxTextLength)))

        #expect(SearchIndexItem(item(text: nil), recognizedText: "").text == nil)
        #expect(SearchIndexItem(item(text: ""), recognizedText: "words").text == "words")
    }
}

struct DeviceConditionsTests {
    @Test func lowPowerHeatOrALowBatteryConstrainTheMac() {
        #expect(!SystemDeviceConditions.isConstrained(lowPowerMode: false, thermalState: .nominal, batteryFraction: nil))
        #expect(!SystemDeviceConditions.isConstrained(lowPowerMode: false, thermalState: .fair, batteryFraction: 0.5))
        #expect(SystemDeviceConditions.isConstrained(lowPowerMode: true, thermalState: .nominal, batteryFraction: nil))
        #expect(SystemDeviceConditions.isConstrained(lowPowerMode: false, thermalState: .serious, batteryFraction: nil))
        #expect(SystemDeviceConditions.isConstrained(lowPowerMode: false, thermalState: .critical, batteryFraction: nil))
        #expect(SystemDeviceConditions.isConstrained(lowPowerMode: false, thermalState: .nominal, batteryFraction: 0.2))
        #expect(!SystemDeviceConditions.isConstrained(lowPowerMode: false, thermalState: .nominal, batteryFraction: 0.21))
    }
}

struct SpotlightWriteTimeoutTests {
    private struct Failure: Error {}

    @Test func aWriteThatIsNeverAnsweredCountsAsTransient() async {
        await #expect(throws: SearchIndexError.transientlyUnavailable(code: SpotlightSearchIndex.timeoutCode)) {
            try await SpotlightSearchIndex.unlessUnanswered(after: .milliseconds(20)) {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }

    @Test func anAnsweredWriteReturnsItsOutcome() async throws {
        try await SpotlightSearchIndex.unlessUnanswered(after: .seconds(60)) {}
        await #expect(throws: Failure.self) {
            try await SpotlightSearchIndex.unlessUnanswered(after: .seconds(60)) { throw Failure() }
        }
    }
}
