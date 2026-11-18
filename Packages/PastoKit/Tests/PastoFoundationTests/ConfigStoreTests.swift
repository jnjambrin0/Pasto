import Foundation
import PastoFoundation
import Testing

private enum Density: String, ConfigValue {
    case compact
    case regular
}

private struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: Int
    var internalModifiers: Int
}

struct ConfigStoreTests {
    private let ephemeral = EphemeralDefaults()
    private var defaults: UserDefaults { ephemeral.defaults }
    private var store: ConfigStore { ConfigStore(defaults: defaults) }

    @Test func resolvesToTheDefaultUntilAValueIsSet() {
        let key = ConfigKey<Int>("historyLimit", default: 30)

        #expect(store.value(for: key) == 30)
        #expect(!store.isSet(key))
        #expect(defaults.object(forKey: "historyLimit") == nil)

        store.set(90, for: key)

        #expect(store.value(for: key) == 90)
        #expect(store.isSet(key))
    }

    @Test func resetGoesBackToTheDefault() {
        let key = ConfigKey<String>("sound", default: "pop")
        store.set("click", for: key)

        store.reset(key)

        #expect(store.value(for: key) == "pop")
        #expect(!store.isSet(key))
    }

    @Test func storesEveryPropertyListType() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        store.set(true, for: ConfigKey<Bool>("bool", default: false))
        store.set(2.5, for: ConfigKey<Double>("double", default: 0))
        store.set(Data([1, 2, 3]), for: ConfigKey<Data>("data", default: Data()))
        store.set(date, for: ConfigKey<Date>("date", default: .distantPast))
        store.set(["a", "b"], for: ConfigKey<[String]>("strings", default: []))

        #expect(store.value(for: ConfigKey<Bool>("bool", default: false)) == true)
        #expect(store.value(for: ConfigKey<Double>("double", default: 0)) == 2.5)
        #expect(store.value(for: ConfigKey<Data>("data", default: Data())) == Data([1, 2, 3]))
        #expect(store.value(for: ConfigKey<Date>("date", default: .distantPast)) == date)
        #expect(store.value(for: ConfigKey<[String]>("strings", default: [])) == ["a", "b"])
    }

    @Test func aValueOfAnotherTypeReadsAsTheDefault() {
        defaults.set("not a number", forKey: "historyLimit")

        #expect(store.value(for: ConfigKey<Int>("historyLimit", default: 30)) == 30)
    }

    @Test func storesEnumerationsAsTheirRawValue() {
        let key = ConfigKey<Density>("density", default: .regular)

        store.set(.compact, for: key)

        #expect(store.value(for: key) == .compact)
        #expect(defaults.string(forKey: "density") == "compact")

        defaults.set("gigantic", forKey: "density")
        #expect(store.value(for: key) == .regular)
    }

    @Test func storesCodableValuesAsJSON() throws {
        let key = ConfigKey("shortcut", default: JSONConfigValue(Shortcut(keyCode: 9, internalModifiers: 1_179_648)))

        #expect(store.value(for: key).value == Shortcut(keyCode: 9, internalModifiers: 1_179_648))

        store.set(JSONConfigValue(Shortcut(keyCode: 8, internalModifiers: 256)), for: key)

        #expect(store.value(for: key).value == Shortcut(keyCode: 8, internalModifiers: 256))
        let stored = try #require(defaults.data(forKey: "shortcut"))
        #expect(String(decoding: stored, as: UTF8.self) == #"{"internalModifiers":256,"keyCode":8}"#)
    }

    @Test func valuesEmitsTheCurrentValueAndThenEachChangeOnce() async {
        let key = ConfigKey<Int>("historyLimit", default: 30)
        var values = store.values(for: key).makeAsyncIterator()

        store.set(90, for: key)
        store.set(90, for: key)
        store.set(true, for: ConfigKey<Bool>("unrelated", default: false))
        store.set(7, for: key)
        store.reset(key)

        #expect(await values.next() == 30)
        #expect(await values.next() == 90)
        #expect(await values.next() == 7)
        #expect(await values.next() == 30)
    }

    @Test func aKeyWhoseNameHasDotsIsObservedToo() async {
        let key = ConfigKey<Int>("tailer.checkpoint.search", default: 0)
        var values = store.values(for: key).makeAsyncIterator()

        store.set(4, for: key)

        #expect(await values.next() == 0)
        #expect(await values.next() == 4)
    }
}
