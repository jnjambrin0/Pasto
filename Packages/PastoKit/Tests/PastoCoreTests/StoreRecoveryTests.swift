import CoreData
import Foundation
@testable import PastoCore
import PastoFoundation
import Testing

/// What happens when the store fails: a save that fails leaves the writer ready for the next
/// one, an unreadable store can be moved aside for a fresh one, and space given up by deletions
/// goes back to the disk.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct StoreRecoveryTests {
    private let folder = TemporaryFolder()

    @Test func aFailedSaveLeavesNothingForTheNextTransaction() async throws {
        let store = try StoreFixture()
        let first = try await store.record(["a"])[0]

        // A save that fails — here an item without its required data, as a full disk would fail
        // it — rolls back everything the transaction did, the changes before the failure included.
        await #expect(throws: (any Error).self) {
            try await store.writer.perform(author: .user) { context in
                try context.setTitle("lost", of: first)
                let orphan = ItemEntity(context: context.context)
                orphan.identifier = "orphan"
                orphan.checksum = "orphan"
                orphan.createdAt = .second(5)
            }
        }

        let second = try await store.record(["b"], startingAt: 2)[0]
        #expect(store.reader.totalItemCount() == 2)
        #expect(store.reader.item(first)?.title == nil)
        #expect(store.reader.item(ItemID(rawValue: "orphan")) == nil)
        #expect(store.reader.itemCollection(for: .clipboard).snapshot.ids == [second, first])
    }

    @Test func anUnreadableStoreIsMovedAsideAndAFreshOneOpens() throws {
        try Data(repeating: 0x42, count: 8_192).write(to: folder.storeURL)

        #expect {
            _ = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "1.0")
        } throws: { error in
            (error as? PersistentStack.LoadError)?.reason == .unreadable
        }

        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let aside = try PersistentStack.moveDamagedStoreAside(at: folder.storeURL, date: date)
        #expect(aside.lastPathComponent.hasPrefix("Pasto-damaged-"))
        #expect(try Data(contentsOf: aside.appending(path: "Pasto.sqlite")) == Data(repeating: 0x42, count: 8_192))

        let stack = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "1.0")
        #expect(StoreReader(stack: stack).totalItemCount() == 0)
        // A second store moved aside the same second does not take the first one's place.
        #expect(try PersistentStack.moveDamagedStoreAside(at: folder.storeURL, date: date) != aside)
    }

    @Test func maintenanceGivesBackTheSpaceOfDeletedItems() async throws {
        let stack = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "1.0")
        let writer = StoreWriter(stack: stack)
        let filler = String(repeating: "pasto ", count: 600)
        _ = try await writer.perform(author: .capture) { context in
            try (0..<1_500).map { try context.record(.text("\($0) \(filler)", at: TimeInterval($0))).id }
        }
        let database = SQLiteInspector(url: folder.storeURL)
        let pagesBefore = Int(try database.strings("PRAGMA page_count")[0])!

        _ = try await writer.perform(author: .user) { try $0.eraseHistory() }
        try await writer.performMaintenance()

        #expect(try database.strings("PRAGMA freelist_count") == ["0"])
        #expect(Int(try database.strings("PRAGMA page_count")[0])! < pagesBefore / 4)
    }

    @Test func aStoreInMemoryHasNothingToMaintain() async throws {
        let store = try StoreFixture()
        #expect(try await store.writer.performMaintenance() == nil)
    }
}
