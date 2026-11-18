import CoreData
import Foundation

// MARK: - Capture

extension WritingContext {
    /// Stores a captured item, or — when an item with the same checksum already exists — moves
    /// that one to the front of the history and credits the copy to its source. Content that
    /// only lived on a pinboard enters the history this way, and stays pinned.
    public func record(_ item: NewItem) throws -> RecordOutcome {
        let application = try item.sourceApplication.map(upserted)

        let newestRequest = ItemEntity.makeRequest(ItemListQuery.inHistory)
        newestRequest.sortDescriptors = ItemListQuery.sortDescriptors(for: .clipboard)
        newestRequest.fetchLimit = 1
        let newestBefore = try context.fetch(newestRequest).first?.identifier

        if let existing = try existingItem(withChecksum: item.checksum) {
            let wasInHistory = existing.timestamp != nil
            // The copy just made replaces what the item held: same content by checksum, but
            // possibly other representations, and a preview built afresh.
            try setContent(of: existing, from: item)
            existing.timestamp = item.timestamp
            // The source is the one of this copy, none included; the device is left alone.
            if existing.sourceApplication !== application {
                existing.sourceApplication = application
            }
            existing.updatedAt = now
            return RecordOutcome(
                id: ItemID(rawValue: existing.identifier),
                kind: wasInHistory ? .movedToFront : .addedToHistory,
                didChangeNewestItem: existing.identifier != newestBefore
            )
        }

        let entity = try inserted(item, timestamp: item.timestamp, sourceApplication: application)
        return RecordOutcome(id: ItemID(rawValue: entity.identifier), kind: .inserted, didChangeNewestItem: true)
    }

    /// "New Text Item" (⌘N): the item with this content — the one already stored, or a new one —
    /// goes to the front of `list`.
    ///
    /// In the history it is recorded as a copy is. On a pinboard it goes first and does **not**
    /// enter the history: an item already in the history keeps its place there, and one already
    /// on that pinboard keeps its place on it (pinning does not reorder). A pinboard that no
    /// longer exists means the history.
    public func create(_ item: NewItem, in list: ListID) throws -> ItemID {
        guard let pinboard = try context.first(ListEntity.self, where: "identifier", equals: list.rawValue),
              pinboard.type == .pinboard
        else {
            return try record(item).id
        }

        let entity: ItemEntity
        if let existing = try existingItem(withChecksum: item.checksum) {
            try setContent(of: existing, from: item)
            existing.updatedAt = now
            entity = existing
        } else {
            entity = try inserted(item, timestamp: nil, sourceApplication: item.sourceApplication.map(upserted))
        }
        let id = ItemID(rawValue: entity.identifier)
        try pin([id], to: list)
        return id
    }

    /// The stored item with this content. Duplicating an item leaves two with one checksum; the
    /// copy the user last touched wins, and any copy in the history comes before one that is on
    /// a pinboard only.
    private func existingItem(withChecksum checksum: String) throws -> ItemEntity? {
        let request = ItemEntity.makeRequest(NSPredicate(format: "checksum == %@", checksum))
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// A new item with this content, made on this device. In the history only with a `timestamp`.
    func inserted(_ item: NewItem, timestamp: Date?, sourceApplication: ApplicationEntity?) throws -> ItemEntity {
        let entity = ItemEntity(context: context)
        entity.identifier = UUID().uuidString
        entity.title = item.title
        entity.timestamp = timestamp
        entity.createdAt = now
        entity.setOrigin(
            device: try context.first(DeviceEntity.self, where: "identifier", equals: localDeviceIdentifier),
            sourceApplication: sourceApplication
        )
        try setContent(of: entity, from: item)
        return entity
    }

    private func setContent(of entity: ItemEntity, from item: NewItem) throws {
        entity.type = item.type
        entity.checksum = item.checksum
        try entity.setPreview(item.preview)

        let data = entity.data ?? ItemDataEntity(context: context)
        try data.setPasteboardItems(item.pasteboardItems)
        entity.data = data
    }
}

// MARK: - Items

extension WritingContext {
    /// Deletes the items outright, wherever they are: what deleting a search result does. To
    /// take items out of one list only, see `remove(_:from:)`.
    public func delete(_ ids: [ItemID]) throws {
        try items(ids).forEach(context.delete)
    }

    /// Fills in a link's preview with what the page at `url` says about itself. The page's
    /// answer replaces the title too, even when it has none. Does nothing if the item is gone,
    /// or no longer a link to `url` — it may have been deleted or edited while the page was
    /// being fetched.
    public func setLinkMetadata(_ metadata: LinkMetadata, of id: ItemID, for url: URL) throws {
        guard let item = try? item(id), case .link(let link) = item.preview, link.url == url else { return }
        try item.setPreview(.link(LinkPreview(
            url: url,
            title: metadata.title,
            iconData: metadata.iconData,
            imageData: metadata.imageData
        )))
        item.updatedAt = now
    }

    public func setTitle(_ title: String?, of id: ItemID) throws {
        let item = try item(id)
        item.title = title
        item.updatedAt = now
    }

    /// Editing: the item keeps its identity, title, place and source, and gets the content,
    /// preview, type and checksum of `newContent`.
    public func replaceContent(of id: ItemID, with newContent: NewItem) throws {
        let item = try item(id)
        try setContent(of: item, from: newContent)
        item.updatedAt = now
    }

    /// Copies an item: the copy goes to the front of the history and, if the item is on a
    /// pinboard, to the end of that pinboard.
    public func duplicate(_ id: ItemID) throws -> ItemID {
        let original = try item(id)

        let copy = ItemEntity(context: context)
        copy.identifier = UUID().uuidString
        copy.checksum = original.checksum
        copy.rawType = original.rawType
        copy.title = original.title
        copy.rawPreview = original.rawPreview
        copy.timestamp = now
        copy.createdAt = now
        copy.setOrigin(
            device: try context.first(DeviceEntity.self, where: "identifier", equals: localDeviceIdentifier),
            sourceApplication: original.sourceApplication
        )

        let data = ItemDataEntity(context: context)
        data.rawPasteboardItems = original.data?.rawPasteboardItems ?? Data()
        copy.data = data

        if let pinboard = original.list {
            copy.displayOrderInPinboard = nextDisplayOrder(in: pinboard)
            copy.list = pinboard
        }
        return ItemID(rawValue: copy.identifier)
    }

    /// Moves an item to the front of the history without capturing it again (it was just
    /// pasted). An item that only lived on a pinboard enters the history, and stays pinned.
    public func touch(_ id: ItemID, at date: Date) throws {
        let item = try item(id)
        item.timestamp = date
        item.updatedAt = now
    }
}

// MARK: - Applications

extension WritingContext {
    /// Creates or updates the application with that bundle identifier.
    ///
    /// A `colorCode` of 0 and a `nil` icon mean "not known", not "remove": capture reports sources
    /// without them and must not erase what was computed later.
    public func upsertApplication(_ application: SourceApplication) throws {
        _ = try upserted(application)
    }

    func upserted(_ application: SourceApplication) throws -> ApplicationEntity {
        let entity: ApplicationEntity
        if let existing = try context.first(ApplicationEntity.self, where: "bundleIdentifier", equals: application.bundleIdentifier) {
            entity = existing
        } else {
            entity = ApplicationEntity(context: context)
            entity.bundleIdentifier = application.bundleIdentifier
            entity.createdAt = now
        }

        // Core Data marks an object as changed even when a setter receives the value it already
        // has, and that would reach persistent history (and sync) on every capture.
        var changed = false
        if entity.name != application.name {
            entity.name = application.name
            changed = true
        }
        if application.colorCode != 0, entity.rawColor != application.colorCode {
            entity.rawColor = application.colorCode
            changed = true
        }
        if let iconData = application.iconData, entity.rawIcon != iconData {
            entity.rawIcon = iconData
            changed = true
        }
        if changed, !entity.isInserted {
            entity.updatedAt = now
        }
        return entity
    }
}
