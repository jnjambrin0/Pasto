import Foundation
import os
import PastoCore
import PastoFoundation
import PastoPicks
import PastoSearch

/// Settings › Privacy › Remove All Data: everything Pasto keeps on this Mac goes, and Pasto quits;
/// the next launch is a first one. The folders go to the Trash, so the history can still be
/// recovered until the user empties it. Privacy permissions stay: only System Settings can take
/// them away.
enum DataRemoval {
    /// Pasto's folders under `~/Library`, by bundle identifier: the store, what suggestions learnt
    /// and the diagnostics; caches; what web previews kept.
    static var folders: [URL] {
        let identifier = AppIdentity.bundleIdentifier
        let library = URL.libraryDirectory
        return [
            AppIdentity.applicationSupportDirectory,
            library.appending(path: "Caches/\(identifier)", directoryHint: .isDirectory),
            library.appending(path: "WebKit/\(identifier)", directoryHint: .isDirectory),
            library.appending(path: "HTTPStorages/\(identifier)", directoryHint: .isDirectory),
            library.appending(path: "HTTPStorages/\(identifier).binarycookies", directoryHint: .notDirectory),
        ]
    }

    /// Removes it all and quits. Nothing may write afterwards, the preferences least of all, so
    /// the process ends here instead of going through the usual termination.
    @MainActor
    static func removeEverythingAndQuit(searchIndex: any SearchIndex, picks: PicksProvider) async -> Never {
        let log = Log.logger(.app)
        log.notice("Removing all of Pasto's data at the user's request")
        await picks.eraseData()
        try? LoginItemService().setEnabled(false)
        ItemRestorer.removeTemporaryImageCopies()
        for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            } catch {
                log.error("Could not move \(folder.lastPathComponent, privacy: .public) to the Trash: \(error)")
            }
        }
        // Last, so that nothing indexed meanwhile stays behind.
        do {
            try await searchIndex.deleteAll()
        } catch {
            log.error("Could not empty the search index: \(error)")
        }
        UserDefaults.standard.removePersistentDomain(forName: AppIdentity.bundleIdentifier)
        // The removal has to reach the preferences daemon before the process is gone.
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        exit(0)
    }
}
