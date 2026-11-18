import Foundation
import PastoCore
import PastoFoundation
@testable import PastoOnboarding
import Testing

/// When the welcome content goes in, and that it never comes back.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WelcomeContentSeederTests {
    private let defaults = EphemeralDefaults()
    private let config: ConfigStore
    private let reader: StoreReader
    private let writer: StoreWriter
    private let seeder: WelcomeContentSeeder

    init() throws {
        config = ConfigStore(defaults: defaults.defaults)
        let stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        reader = StoreReader(stack: stack)
        writer = StoreWriter(stack: stack)
        seeder = WelcomeContentSeeder(
            config: config,
            writer: writer,
            application: FrontmostApplication(bundleIdentifier: "jnjambrino.Pasto", name: "Pasto", icon: nil),
            strings: WelcomeContentStrings(languageCode: "en")!
        )
    }

    private var historyCount: Int {
        reader.itemCount(in: .clipboard)
    }

    private var pinboards: [ClipList] {
        reader.lists().filter { $0.type == .pinboard }
    }

    @Test func aFirstLaunchGetsTheContentOnce() async throws {
        #expect(await seeder.seedIfNeeded() == .seeded)

        #expect(historyCount == 3)
        #expect(pinboards.map(\.name) == ["Pasto Links"])
        #expect(reader.itemCount(in: try #require(pinboards.first).id) == 4)
        #expect(config.value(for: .isWelcomeContentSeeded))

        #expect(await seeder.seedIfNeeded() == .notNeeded)
        #expect(historyCount == 3)
        #expect(pinboards.count == 1)
    }

    @Test func anUpdateFromAnEarlierVersionGetsNothing() async {
        config.recordLaunch(of: AppVersion(major: 1, minor: 0, patch: 2))

        #expect(await seeder.seedIfNeeded() == .notNeeded)

        #expect(historyCount == 0)
        #expect(pinboards.isEmpty)
        #expect(!config.value(for: .isWelcomeContentSeeded))
    }

    @Test func deletedContentDoesNotComeBack() async throws {
        #expect(await seeder.seedIfNeeded() == .seeded)
        let pinboard = try #require(pinboards.first)
        try await writer.perform(author: .user) { context in
            _ = try context.eraseHistory()
            try context.deleteList(pinboard.id)
        }

        // Even if this were a first launch again: the installation already had it.
        #expect(await seeder.seedIfNeeded() == .notNeeded)

        #expect(historyCount == 0)
        #expect(pinboards.isEmpty)
    }

    @Test func aLaunchCutShortAfterTheWriteDoesNotSeedTwice() async throws {
        #expect(await seeder.seedIfNeeded() == .seeded)
        // The process died before the installation was marked.
        config.reset(.isWelcomeContentSeeded)

        #expect(await seeder.seedIfNeeded() == .storeNotNew)

        #expect(historyCount == 3)
        #expect(pinboards.count == 1)
        #expect(config.value(for: .isWelcomeContentSeeded))
    }

    @Test func aStoreThatIsNotNewGetsNothingAndIsNotAskedAgain() async throws {
        _ = try await writer.perform(author: .user) { try $0.createPinboard(name: "Mine", color: .blue) }

        #expect(await seeder.seedIfNeeded() == .storeNotNew)

        #expect(historyCount == 0)
        #expect(pinboards.map(\.name) == ["Mine"])
        #expect(config.value(for: .isWelcomeContentSeeded))
    }
}
