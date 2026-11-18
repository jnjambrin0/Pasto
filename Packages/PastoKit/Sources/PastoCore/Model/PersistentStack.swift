import CoreData
import Foundation
import os
import PastoFoundation

/// Pasto's Core Data store: the container, its read-only view context and the two rows every
/// store needs (the clipboard history list and this Mac's device).
///
/// Readers and the writer are built from it: `StoreReader`, `StoreWriter`, `HistoryTailer`.
public final class PersistentStack: Sendable {
    public enum Location: Sendable {
        case onDisk(URL)
        /// A private SQLite database that lives in memory. Unlike Core Data's in-memory store type
        /// it keeps persistent history and enforces uniqueness constraints, like a store on disk.
        case inMemory
    }

    /// The store could not be opened. Nothing is deleted or reset: the files stay as they were —
    /// after a failed migration, as they were before it.
    public struct LoadError: Error {
        public enum Reason: Sendable, Equatable {
            /// The files cannot be read as a store: damaged, or not a store at all. Starting over
            /// with `moveDamagedStoreAside(at:)` is the way out.
            case unreadable
            /// Bringing the store to the current model failed; it is back as it was.
            case migrationFailed
            /// A newer version of Pasto wrote it, and this one cannot open it without losing what
            /// that one added.
            case createdByNewerVersion
        }

        public let reason: Reason
        public let underlying: any Error
    }

    /// Where the app keeps its store (creating the stack is what creates the file).
    public static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: Log.subsystem, directoryHint: .isDirectory)
            .appending(path: "Pasto.sqlite", directoryHint: .notDirectory)
    }

    let container: NSPersistentContainer
    /// `DeviceEntity.identifier` of this Mac in this store.
    let localDeviceIdentifier: String

    /// Opens the store, creating it if needed, and migrates it to the current model first if an
    /// older version created it.
    ///
    /// - Parameters:
    ///   - deviceName: How this Mac is called on the items it copies.
    ///   - appVersion: The running version of Pasto, recorded on this Mac's device row.
    public convenience init(
        location: Location,
        deviceName: String = Host.current().localizedName ?? "Mac",
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    ) throws {
        try self.init(location: location, deviceName: deviceName, appVersion: appVersion, didMigrate: nil)
    }

    /// - Parameter didMigrate: Runs after each migration step; a throw makes the migration fail.
    init(
        location: Location,
        deviceName: String,
        appVersion: String,
        didMigrate: (@Sendable () throws -> Void)?
    ) throws {
        let description = NSPersistentStoreDescription()
        description.type = NSSQLiteStoreType
        /// The copy of a store being migrated, until the migration is over.
        var backup: (files: StoreFiles, folder: URL)?
        switch location {
        case .onDisk(let url):
            let files = StoreFiles(url: url)
            do {
                try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
                try StoreMigration.recoverFromUnfinishedMigration(of: files)
                switch try StoreMigration.need(at: url) {
                case .nothing:
                    break
                case .migration:
                    backup = (files, try StoreMigration.backUp(files))
                case .newerVersion:
                    throw LoadError(reason: .createdByNewerVersion, underlying: CocoaError(.persistentStoreIncompatibleVersionHash))
                }
            } catch let error as LoadError {
                throw error
            } catch {
                throw LoadError(reason: .unreadable, underlying: error)
            }
            description.url = url
        case .inMemory:
            description.url = URL(filePath: "/dev/null")
        }
        // Loading synchronously lets the initializer report the failure.
        description.shouldAddStoreAsynchronously = false
        // History feeds `HistoryTailer`; the remote-change notification is what wakes it up.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(StoreMigration.manager(didMigrate: didMigrate), forKey: NSPersistentStoreStagedMigrationManagerOptionKey)

        container = NSPersistentContainer(name: "Pasto", managedObjectModel: PastoModelV2.model)
        container.persistentStoreDescriptions = [description]

        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            guard let backup else {
                throw LoadError(reason: .unreadable, underlying: loadError)
            }
            do {
                try backup.files.restore(from: backup.folder)
            } catch {
                Log.logger(.store).fault("Could not put back the store after a failed migration: \(error)")
            }
            throw LoadError(reason: .migrationFailed, underlying: loadError)
        }
        if let backup {
            // The store has the current model now: the copy has done its job.
            try? FileManager.default.removeItem(at: backup.folder)
        }

        // Read-only by convention: every write goes through `StoreWriter` and arrives here merged.
        container.viewContext.automaticallyMergesChangesFromParent = true

        do {
            localDeviceIdentifier = try Self.seed(container, deviceName: deviceName, appVersion: appVersion)
        } catch {
            throw LoadError(reason: .unreadable, underlying: error)
        }
    }

    // MARK: - Starting over

    /// Moves the store at `url` — every one of its files — into a folder next to it named after it
    /// and `date` (`Pasto-damaged-2026-11-20-153000`), where it stays as it was for whoever wants
    /// to look at it, and returns that folder. A stack opened at `url` afterwards starts with an
    /// empty store. For a store that fails to open as `LoadError.Reason.unreadable`.
    public static func moveDamagedStoreAside(at url: URL = defaultStoreURL, date: Date = Date()) throws -> URL {
        let files = StoreFiles(url: url)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stem = url.deletingPathExtension().lastPathComponent
        var folder = files.directory.appending(path: "\(stem)-damaged-\(formatter.string(from: date))", directoryHint: .isDirectory)
        var attempt = 1
        while FileManager.default.fileExists(atPath: folder.path) {
            attempt += 1
            folder = files.directory.appending(path: "\(stem)-damaged-\(formatter.string(from: date))-\(attempt)", directoryHint: .isDirectory)
        }
        try files.move(into: folder)
        return folder
    }

    // MARK: - Seeding

    private static let localDeviceMetadataKey = "PastoLocalDeviceIdentifier"

    /// Makes sure the clipboard history list and this Mac's device exist, and returns the device's
    /// identifier. Runs on every load and only writes what is missing or outdated.
    private static func seed(_ container: NSPersistentContainer, deviceName: String, appVersion: String) throws -> String {
        let context = container.newBackgroundContext()
        context.transactionAuthor = TransactionAuthor.maintenance.rawValue

        return try context.performAndWait {
            let now = Date()

            if try context.first(ListEntity.self, where: "identifier", equals: ListID.clipboard.rawValue) == nil {
                let list = ListEntity(context: context)
                list.identifier = ListID.clipboard.rawValue
                list.type = .clipboard
                try list.setAttributes(.clipboard(capacity: .month))
                list.createdAt = now

                let metadata = ListMetadataEntity(context: context)
                metadata.identifier = list.identifier
                metadata.index = 0
                metadata.createdAt = now
                list.metadata = metadata
            }

            // This Mac's identity is born with the store and kept in its metadata, so it survives
            // as long as the data it is attached to and needs nothing from the system.
            let coordinator = container.persistentStoreCoordinator
            let store = coordinator.persistentStores[0]
            var storeMetadata = coordinator.metadata(for: store)
            let deviceIdentifier = storeMetadata[localDeviceMetadataKey] as? String ?? UUID().uuidString
            if storeMetadata[localDeviceMetadataKey] == nil {
                storeMetadata[localDeviceMetadataKey] = deviceIdentifier
                coordinator.setMetadata(storeMetadata, for: store)
            }

            if let device = try context.first(DeviceEntity.self, where: "identifier", equals: deviceIdentifier) {
                if device.name != deviceName || device.appVersion != appVersion {
                    device.name = deviceName
                    device.appVersion = appVersion
                    device.updatedAt = now
                }
            } else {
                let device = DeviceEntity(context: context)
                device.identifier = deviceIdentifier
                device.name = deviceName
                device.type = .mac
                device.appVersion = appVersion
                device.createdAt = now
            }

            if context.hasChanges {
                try context.save()
            }
            return deviceIdentifier
        }
    }
}
