import CoreData
import Foundation
@testable import PastoCore
import PastoFoundation
import Testing

/// A store written by version 1 of the schema opens with version 2, keeping everything.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct StoreMigrationTests {
    private let folder: TemporaryFolder

    init() throws {
        folder = TemporaryFolder()
    }

    private func externalFiles() throws -> [String] {
        let external = folder.url.appending(path: ".Pasto_SUPPORT/_EXTERNAL_DATA")
        return try FileManager.default.contentsOfDirectory(atPath: external.path).sorted()
    }

    @Test func aVersionOneStoreKeepsItsItemsListsDataAndHistory() async throws {
        let contents = try VersionOneStore.create(at: folder.storeURL)
        let externalBefore = try externalFiles()
        #expect(!externalBefore.isEmpty)
        #expect(try StoreMigration.need(at: folder.storeURL) == .migration)

        let stack = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Old Mac", appVersion: "1.0")
        let reader = StoreReader(stack: stack)

        #expect(try StoreMigration.need(at: folder.storeURL) == .nothing)
        #expect(reader.itemCollection(for: .clipboard).snapshot.ids == contents.historyItems.map(ItemID.init))
        let pinboard = ListID(rawValue: VersionOneStore.pinboardIdentifier)
        #expect(reader.itemCollection(for: pinboard).snapshot.ids == contents.pinboardItems.map(ItemID.init))
        #expect(reader.lists().map(\.id) == [.clipboard, pinboard])
        #expect(reader.historyCapacity == .unlimited)

        let large = try #require(reader.item(ItemID(rawValue: contents.largeItem)))
        #expect(large.device?.name == "Old Mac")
        #expect(large.sourceApplication?.name == "Safari")
        #expect(large.listID == pinboard)
        #expect(reader.pasteboardItems(for: large.id) == contents.largePasteboardItems)
        #expect(try externalFiles() == externalBefore)

        // The seed found this Mac in the store instead of adding another one.
        #expect(reader.deviceNames() == ["Old Mac"])

        // The indexes of version 2 exist, and the history before the migration is still there.
        let indexes = try SQLiteInspector(url: folder.storeURL).indexNames
        for index in PastoModelV2.addedItemIndexes {
            #expect(indexes.contains("Z_ItemEntity_\(index.name)"))
        }
        let context = stack.container.newBackgroundContext()
        let transactions = try await context.perform {
            let result = try context.execute(NSPersistentHistoryChangeRequest.fetchHistory(after: contents.historyToken)) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.count ?? 0
        }
        // The save that added the third item, and possibly the migration's own empty one.
        #expect(transactions >= 1)

        // The copy kept during the migration is gone.
        #expect(try folder.entries() == ["Pasto.sqlite", "Pasto.sqlite-wal", "Pasto.sqlite-shm", ".Pasto_SUPPORT"])

        // And the migrated store takes writes as any other.
        let writer = StoreWriter(stack: stack)
        let recorded = try await writer.perform(author: .capture) { try $0.record(.text("new", at: 3_000)).id }
        #expect(reader.itemCollection(for: .clipboard).snapshot.ids == [recorded] + contents.historyItems.map(ItemID.init))
    }

    @Test func aFailedMigrationLeavesTheStoreAsItWas() async throws {
        _ = try VersionOneStore.create(at: folder.storeURL)
        let database = SQLiteInspector(url: folder.storeURL)
        let rowsBefore = try database.dump()
        let externalBefore = try folder.contents().filter { $0.key.contains("_EXTERNAL_DATA") }

        struct Refused: Error {}
        #expect {
            _ = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "2.0", didMigrate: { throw Refused() })
        } throws: { error in
            (error as? PersistentStack.LoadError)?.reason == .migrationFailed
        }

        // Byte for byte, the database may differ: opening it at all folds its write-ahead log in.
        // Every row, the schema and the external files are as they were.
        #expect(try database.dump() == rowsBefore)
        #expect(try folder.contents().filter { $0.key.contains("_EXTERNAL_DATA") } == externalBefore)
        #expect(try !folder.entries().contains { $0.contains("backup") })
        #expect(try StoreMigration.need(at: folder.storeURL) == .migration)

        // Nothing stands in the way of trying again.
        let stack = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "2.0")
        #expect(StoreReader(stack: stack).totalItemCount() == 3)
    }

    @Test func aMigrationThatNeverFinishedStartsAgainFromTheCopy() async throws {
        _ = try VersionOneStore.create(at: folder.storeURL)
        let files = StoreFiles(url: folder.storeURL)
        _ = try StoreMigration.backUp(files)
        // Pasto stopped half-way through: the store is in pieces.
        try Data("half-migrated".utf8).write(to: folder.storeURL)

        let stack = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "2.0")

        #expect(StoreReader(stack: stack).totalItemCount() == 3)
        #expect(!FileManager.default.fileExists(atPath: StoreMigration.backupFolder(for: files).path))
    }

    @Test func aPartialCopyIsDiscardedAndTheStoreIsLeftAlone() async throws {
        _ = try VersionOneStore.create(at: folder.storeURL)
        let partial = folder.url.appending(path: "Pasto-migration-backup.partial")
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: false)
        try Data("incomplete".utf8).write(to: partial.appending(path: "Pasto.sqlite"))

        let stack = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "2.0")

        #expect(StoreReader(stack: stack).totalItemCount() == 3)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test func aStoreFromANewerVersionIsNotTouched() throws {
        let newer = PastoModelV1.makeModel(bindsClasses: false)
        newer.entitiesByName["ItemEntity"]!.versionHashModifier = "from the future"
        let description = NSPersistentStoreDescription(url: folder.storeURL)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentContainer(name: "Newer", managedObjectModel: newer)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        let before = try folder.contents()

        #expect {
            _ = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "1.0")
        } throws: { error in
            (error as? PersistentStack.LoadError)?.reason == .createdByNewerVersion
        }
        #expect(try folder.contents() == before)
    }

    @Test func aNewStoreHasTheCurrentModelAndReclaimsSpaceIncrementally() throws {
        _ = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "1.0")

        let inspector = SQLiteInspector(url: folder.storeURL)
        #expect(try inspector.strings("PRAGMA auto_vacuum") == ["2"])
        for index in PastoModelV2.addedItemIndexes {
            #expect(try inspector.indexNames.contains("Z_ItemEntity_\(index.name)"))
        }
    }
}
