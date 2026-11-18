import CoreData
import Foundation
@testable import PastoCore
import SQLite3

/// The folder as the home of one test's store.
extension TemporaryFolder {
    var storeURL: URL {
        url.appending(path: "Pasto.sqlite")
    }

    /// Every file under the folder with its contents, by path relative to it: to tell whether
    /// anything changed.
    func contents() throws -> [String: Data] {
        var contents: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            contents[String(file.path.dropFirst(url.path.count))] = try Data(contentsOf: file)
        }
        return contents
    }

    /// Names of the entries directly in the folder.
    func entries() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: url.path))
    }
}

/// A store as version 1 of Pasto wrote it, built with the frozen V1 model and nothing else.
enum VersionOneStore {
    static let deviceIdentifier = "V1-DEVICE"
    static let pinboardIdentifier = "V1-PINBOARD"

    struct Contents {
        /// In the history, newest first.
        var historyItems: [String]
        /// On the pinboard, in its order.
        var pinboardItems: [String]
        /// The item whose pasteboard data is large enough for external storage, and that data.
        var largeItem: String
        var largePasteboardItems: [PasteboardItemSnapshot]
        /// The persistent history position after the first save.
        var historyToken: NSPersistentHistoryToken?
    }

    /// Creates the store at `url`: the clipboard history list, a pinboard, this Mac, an
    /// application and three items — one only in the history, one in the history and pinned
    /// with megabytes of data, one only on the pinboard.
    static func create(at url: URL) throws -> Contents {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        let container = NSPersistentContainer(name: "V1", managedObjectModel: PastoModelV1.model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let coordinator = container.persistentStoreCoordinator
        let store = coordinator.persistentStores[0]
        var metadata = coordinator.metadata(for: store)
        metadata["PastoLocalDeviceIdentifier"] = deviceIdentifier
        coordinator.setMetadata(metadata, for: store)

        let large = [PasteboardItemSnapshot(types: ["public.png"], dataByType: ["public.png": Data((0..<3_000_000).map { UInt8($0 % 251) })])]
        let context = container.newBackgroundContext()
        // Closed before returning — its log folded in — as Pasto closes it when it quits: a store
        // still open in the background would be copied or replaced under its feet.
        defer { try? coordinator.remove(store) }
        return try context.performAndWait {
            let model = PastoModelV1.model
            func insert(_ entity: String, _ values: [String: Any]) -> NSManagedObject {
                let object = NSManagedObject(entity: model.entitiesByName[entity]!, insertInto: context)
                object.setValuesForKeys(values)
                return object
            }
            let created = Date(timeIntervalSinceReferenceDate: 100)
            let history = insert("ListEntity", [
                "identifier": ListID.clipboard.rawValue, "rawType": ListType.clipboard.rawValue,
                "rawAttributes": try BinaryPropertyList.encode(ListAttributes.clipboard(capacity: .unlimited)), "createdAt": created,
            ])
            history.setValue(insert("ListMetadataEntity", ["identifier": ListID.clipboard.rawValue, "index": 0, "createdAt": created]), forKey: "metadata")
            let pinboard = insert("ListEntity", [
                "identifier": pinboardIdentifier, "name": "Work", "rawType": ListType.pinboard.rawValue,
                "rawAttributes": try BinaryPropertyList.encode(ListAttributes.pinboard(color: .blue)), "createdAt": created,
            ])
            pinboard.setValue(insert("ListMetadataEntity", ["identifier": pinboardIdentifier, "index": 1, "createdAt": created]), forKey: "metadata")
            let device = insert("DeviceEntity", ["identifier": deviceIdentifier, "name": "Old Mac", "appVersion": "1.0", "createdAt": created])
            let application = insert("ApplicationEntity", ["bundleIdentifier": "com.apple.Safari", "name": "Safari", "createdAt": created])

            func item(_ identifier: String, timestamp: TimeInterval?, pinned order: Int64?, pasteboardItems: [PasteboardItemSnapshot]) throws {
                let item = insert("ItemEntity", [
                    "identifier": identifier, "checksum": "checksum-\(identifier)", "rawType": ItemType.text.rawValue,
                    "rawPreview": try BinaryPropertyList.encode(ItemPreview.text(TextPreview(text: identifier, characterCount: identifier.count))),
                    "createdAt": created, "displayOrderInPinboard": order ?? 0,
                ])
                item.setValue(timestamp.map { Date(timeIntervalSinceReferenceDate: $0) }, forKey: "timestamp")
                item.setValue(order == nil ? nil : pinboard, forKey: "list")
                item.setValue(device, forKey: "device")
                item.setValue(application, forKey: "sourceApplication")
                item.setValue(insert("ItemDataEntity", ["rawPasteboardItems": try BinaryPropertyList.encode(pasteboardItems)]), forKey: "data")
            }
            let small = [PasteboardItemSnapshot(types: ["public.utf8-plain-text"], dataByType: ["public.utf8-plain-text": Data("a".utf8)])]
            try item("A", timestamp: 1_000, pinned: nil, pasteboardItems: small)
            try item("B", timestamp: 2_000, pinned: 0, pasteboardItems: large)
            try context.save()
            let token = coordinator.currentPersistentHistoryToken(fromStores: nil)
            try item("C", timestamp: nil, pinned: 1, pasteboardItems: small)
            try context.save()
            return Contents(historyItems: ["B", "A"], pinboardItems: ["B", "C"], largeItem: "B", largePasteboardItems: large, historyToken: token)
        }
    }
}

/// Reads a SQLite database directly, beside Core Data: what the schema and the file look like.
struct SQLiteInspector {
    let url: URL

    /// The first column of every row `query` returns, as text.
    func strings(_ query: String, column: Int32 = 0) throws -> [String] {
        // Read-write, though it only reads: a read-only connection cannot open a database in WAL
        // mode whose shared-memory file is not there.
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "")
        }
        return rows
    }

    /// The schema and every row of every table, as text.
    func dump() throws -> [String] {
        var lines = try strings("SELECT type || ' ' || name || ' ' || coalesce(sql, '') FROM sqlite_master ORDER BY name")
        for table in try strings("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") {
            let columns = try strings("SELECT name FROM pragma_table_info('\(table)')")
            let row = columns.map { "quote(\"\($0)\")" }.joined(separator: " || ',' || ")
            lines += try strings("SELECT '\(table): ' || \(row) FROM \"\(table)\" ORDER BY rowid")
        }
        return lines
    }

    var indexNames: Set<String> {
        get throws { Set(try strings("SELECT name FROM sqlite_master WHERE type = 'index'")) }
    }

    /// What SQLite would do to run `query`, one step per line joined with " | ".
    func plan(_ query: String) throws -> String {
        try strings("EXPLAIN QUERY PLAN " + query, column: 3).joined(separator: " | ")
    }
}
