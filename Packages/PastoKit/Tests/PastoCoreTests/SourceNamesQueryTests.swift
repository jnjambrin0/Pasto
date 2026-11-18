import CoreData
import Foundation
@testable import PastoCore
import Testing

/// The names search suggests are read straight from SQLite on a store on disk
/// (`SourceNamesQuery`). They must be the ones Core Data's "has items" gives.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SourceNamesQueryTests {
    private let folder = TemporaryFolder()

    /// The names as Core Data reads them.
    private func coreDataNames(of entityName: String, in stack: PersistentStack) throws -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["name"]
        request.returnsDistinctResults = true
        request.predicate = NSPredicate(format: "items.@count > 0")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try stack.container.viewContext.fetch(request).compactMap { $0["name"] as? String }
    }

    @Test func theNamesAreThoseOfApplicationsAndDevicesWithItems() async throws {
        let stack = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Este Mac", appVersion: "1.0")
        let reader = StoreReader(stack: stack)
        let writer = StoreWriter(stack: stack, now: { StoreFixture.now })
        let applications = ["Zeta", "árbol", "Árbol", "notes", "Notes", "Zeta"].enumerated().map { index, name in
            SourceApplication(bundleIdentifier: "com.example.\(index)", name: name)
        }

        let ids = try await writer.perform(author: .capture) { context in
            try applications.enumerated().map { index, application in
                try context.record(.text("item \(index)", at: TimeInterval(index + 1), from: application)).id
            }
        }
        try await writer.perform(author: .user) { context in
            // An application whose items are all gone, and one that never had any.
            try context.delete([ids[3]])
            try context.upsertApplication(SourceApplication(bundleIdentifier: "com.example.empty", name: "Empty"))
        }
        // A device with no items, and one without a name.
        try writer.context.performAndWait {
            let device = DeviceEntity(context: writer.context)
            device.identifier = "OTHER"
            device.name = "Otro Mac"
            device.createdAt = StoreFixture.now
            try writer.context.save()
        }

        let applicationNames = try #require(SourceNamesQuery.names(of: .application, inStoreAt: folder.storeURL))
        #expect(applicationNames == (try coreDataNames(of: ApplicationEntity.entityName, in: stack)))
        #expect(applicationNames == ["Notes", "Zeta", "Árbol", "árbol"])
        #expect(reader.sourceApplicationNames() == applicationNames)

        let deviceNames = try #require(SourceNamesQuery.names(of: .device, inStoreAt: folder.storeURL))
        #expect(deviceNames == (try coreDataNames(of: DeviceEntity.entityName, in: stack)))
        #expect(deviceNames == ["Este Mac"])
        #expect(reader.deviceNames() == deviceNames)
    }

    @Test func aStoreInMemoryIsAskedThroughCoreData() async throws {
        let store = try StoreFixture()
        try await store.writer.perform(author: .capture) { context in
            _ = try context.record(.text("a", at: 1, from: SourceApplication(bundleIdentifier: "com.example.a", name: "A")))
        }
        #expect(store.reader.sourceApplicationNames() == ["A"])
        #expect(store.reader.deviceNames() == ["Test Mac"])
    }
}
