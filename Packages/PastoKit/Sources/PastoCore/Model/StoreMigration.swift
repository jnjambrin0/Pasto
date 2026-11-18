import CoreData
import os
import PastoFoundation

/// Brings a store on disk to the current model as it is opened, with a copy of it kept until that
/// has worked.
///
/// The models are built in code, so Core Data cannot find the one a store was created with by
/// itself; a staged migration names them. Every step so far is lightweight: Core Data rewrites the
/// tables in place with SQL, keeping the rows, their primary keys, the files of external storage
/// and the persistent history.
enum StoreMigration {
    /// What a store on disk needs before the current model can open it.
    enum Need: Equatable {
        /// It does not exist yet, or it already has the current model.
        case nothing
        /// It has an older model this version knows how to migrate from.
        case migration
        /// It was written by a newer version of Pasto: there is no going back to this model.
        case newerVersion
    }

    static func need(at url: URL) throws -> Need {
        guard FileManager.default.fileExists(atPath: url.path) else { return .nothing }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        if PastoModelV2.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
            return .nothing
        }
        if PastoModelV1.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
            return .migration
        }
        return .newerVersion
    }

    /// The steps from every model a store may have been created with to the current one.
    ///
    /// - Parameter didMigrate: Runs after each step, on the migrated store; a throw fails the
    ///   migration (tests use it to make one fail).
    static func manager(didMigrate: (@Sendable () throws -> Void)? = nil) -> NSStagedMigrationManager {
        let stage = NSCustomMigrationStage(
            migratingFrom: reference(to: PastoModelV1.model),
            to: reference(to: PastoModelV2.model)
        )
        stage.label = "V1 → V2: fetch indexes for the history, pinboards and retention"
        if let didMigrate {
            stage.didMigrateHandler = { _, _ in try didMigrate() }
        }
        return NSStagedMigrationManager([stage])
    }

    private static func reference(to model: NSManagedObjectModel) -> NSManagedObjectModelReference {
        NSManagedObjectModelReference(model: model, versionChecksum: model.versionChecksum)
    }

    // MARK: - The copy kept meanwhile

    /// Copies the store before it is migrated, and returns where the copy is. The copy is made
    /// under a provisional name and renamed once whole, so a copy under the final name is always
    /// complete.
    static func backUp(_ files: StoreFiles) throws -> URL {
        let backup = backupFolder(for: files)
        let partial = partialBackupFolder(for: files)
        try? FileManager.default.removeItem(at: partial)
        try files.copy(into: partial)
        try FileManager.default.moveItem(at: partial, to: backup)
        return backup
    }

    /// Settles what a migration that never finished — Pasto stopped half-way — left behind: a
    /// whole copy means the store may be half-migrated, so the copy goes back in its place and
    /// the migration runs again; a partial copy means the store was not touched yet.
    static func recoverFromUnfinishedMigration(of files: StoreFiles) throws {
        try? FileManager.default.removeItem(at: partialBackupFolder(for: files))
        let backup = backupFolder(for: files)
        guard FileManager.default.fileExists(atPath: backup.path) else { return }
        Log.logger(.store).error("Putting back the store a migration did not finish with")
        try files.restore(from: backup)
    }

    /// Where the copy of a store being migrated waits: next to it, until the migration is over.
    static func backupFolder(for files: StoreFiles) -> URL {
        files.directory.appending(path: "\(stem(of: files))-migration-backup", directoryHint: .isDirectory)
    }

    private static func partialBackupFolder(for files: StoreFiles) -> URL {
        files.directory.appending(path: "\(stem(of: files))-migration-backup.partial", directoryHint: .isDirectory)
    }

    private static func stem(of files: StoreFiles) -> String {
        files.url.deletingPathExtension().lastPathComponent
    }
}
