import Foundation
import PastoCore
@testable import PastoPicks
import Testing

struct ItemClassStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "PastoPicksTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var url: URL { directory.appending(path: "item-classes.jsonl") }
    private let item = ItemID(rawValue: "item")

    @Test func theModelsClassComesBeforeTheRules() async throws {
        defer { cleanUp() }
        let store = ItemClassStore(url: url)
        #expect(await store.itemClass(of: item) == nil)
        await store.setRuleClass(.unclassified, for: item)
        #expect(await store.itemClass(of: item) == .unclassified)
        #expect(await !store.hasModelClass(for: item))
        try await store.setModelClass(.message, for: item)
        #expect(await store.itemClass(of: item) == .message)
        #expect(await store.hasModelClass(for: item))
    }

    @Test func onlyTheModelsAnswersAreKeptOnDisk() async throws {
        defer { cleanUp() }
        let store = ItemClassStore(url: url)
        await store.setRuleClass(.command, for: ItemID(rawValue: "ruled"))
        try await store.setModelClass(.unclassified, for: item)

        let reopened = ItemClassStore(url: url)
        #expect(await reopened.itemClass(of: ItemID(rawValue: "ruled")) == nil)
        #expect(await reopened.hasModelClass(for: item))
        // An item has no class until the rules have looked at it in this run; then the model's
        // answer, even "none of those", takes their place.
        #expect(await reopened.itemClass(of: item) == nil)
        #expect(await reopened.setRuleClass(.filePath, for: item) == .unclassified)
        #expect(await reopened.itemClass(of: item) == .unclassified)
    }

    @Test func aSecretFoundByTheRulesStands() async throws {
        defer { cleanUp() }
        let store = ItemClassStore(url: url)
        try await store.setModelClass(.message, for: item)
        #expect(await store.setRuleClass(.secret, for: item) == .secret)
        #expect(await store.itemClass(of: item) == .secret)
    }

    @Test func theNewestRecordsStayWithinTheCapacity() async throws {
        defer { cleanUp() }
        let store = ItemClassStore(url: url, capacity: 3)
        for index in 0..<5 {
            try await store.setModelClass(.quote, for: ItemID(rawValue: "item-\(index)"))
        }
        let reopened = ItemClassStore(url: url, capacity: 3)
        #expect(await !reopened.hasModelClass(for: ItemID(rawValue: "item-1")))
        #expect(await reopened.hasModelClass(for: ItemID(rawValue: "item-2")))
        #expect(await reopened.hasModelClass(for: ItemID(rawValue: "item-4")))
    }

    @Test func erasingForgetsEverything() async throws {
        defer { cleanUp() }
        let store = ItemClassStore(url: url)
        await store.setRuleClass(.command, for: ItemID(rawValue: "ruled"))
        try await store.setModelClass(.quote, for: item)
        try await store.erase()
        #expect(await store.itemClass(of: item) == nil)
        #expect(await store.itemClass(of: ItemID(rawValue: "ruled")) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
