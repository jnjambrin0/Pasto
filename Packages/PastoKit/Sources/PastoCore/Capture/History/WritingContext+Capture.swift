import CoreData
import Foundation

// What capture needs from the store besides `record(_:)`.

extension WritingContext {
    /// The application stored under that bundle identifier, with its icon and colour.
    func sourceApplication(bundleIdentifier: String) throws -> SourceApplication? {
        try context
            .first(ApplicationEntity.self, where: "bundleIdentifier", equals: bundleIdentifier)
            .map(SourceApplication.init)
    }

    /// Lets the context forget what it holds of an item once it is saved: the item and its data
    /// keep each other alive, so without this the encoded pasteboard data of every capture —
    /// as large as the copy itself — stays in memory for as long as the writer does. The store
    /// keeps everything; the next read faults it back in.
    func releaseContent(of id: ItemID) {
        let request = ItemEntity.makeRequest(NSPredicate(format: "identifier == %@", id.rawValue))
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = true
        guard let item = try? context.fetch(request).first, !item.hasChanges else { return }
        if let data = item.data, !data.hasChanges {
            context.refresh(data, mergeChanges: false)
        }
        context.refresh(item, mergeChanges: false)
    }
}
