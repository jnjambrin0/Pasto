import CoreData
import Foundation

// MARK: - Recording

extension WritingContext {
    /// The inverse of what this transaction has done to the items so far. Read from the
    /// context's unsaved changes, so it holds for whatever operations ran, and it must be asked
    /// for before the transaction is saved.
    func reversalOfPendingChanges() -> ItemChangeReversal {
        // Settles the bookkeeping first: an item created and deleted in this transaction then
        // counts as neither.
        context.processPendingChanges()

        var reversal = ItemChangeReversal()
        reversal.inserted = context.insertedObjects.compactMap { ($0 as? ItemEntity)?.identifier }
        reversal.deleted = context.deletedObjects.compactMap { ($0 as? ItemEntity).flatMap(Self.deletedItem) }
        for case let item as ItemEntity in context.updatedObjects {
            let values = Self.savedPlacementValues(of: item, changedKeys: item.changedValues().keys)
            if !values.isEmpty { reversal.changed[item.identifier] = values }
        }
        return reversal
    }

    /// The values the store holds, not the ones the transaction has set: a deleted object's own
    /// properties are no longer reliable, and a changed one's are the new values.
    private static func saved<Value>(_ key: String, of object: NSManagedObject) -> Value? {
        object.committedValues(forKeys: [key])[key] as? Value
    }

    /// The saved values of the parts of the placement among `changedKeys`, in a fixed order.
    private static func savedPlacementValues(
        of item: ItemEntity,
        changedKeys: some Collection<String>
    ) -> [ItemChangeReversal.PlacementValue] {
        let changed = Set(changedKeys)
        var values: [ItemChangeReversal.PlacementValue] = []
        if changed.contains("title") {
            values.append(.title(saved("title", of: item)))
        }
        if changed.contains("timestamp") {
            values.append(.timestamp(saved("timestamp", of: item)))
        }
        if changed.contains("list") {
            let list: ListEntity? = saved("list", of: item)
            values.append(.pinboard(list.flatMap { saved("identifier", of: $0) }))
        }
        if changed.contains("displayOrderInPinboard") {
            values.append(.displayOrderInPinboard(saved("displayOrderInPinboard", of: item) ?? 0))
        }
        return values
    }

    private static func savedPlacement(of item: ItemEntity) -> ItemChangeReversal.Placement {
        let list: ListEntity? = saved("list", of: item)
        return ItemChangeReversal.Placement(
            title: saved("title", of: item),
            timestamp: saved("timestamp", of: item),
            pinboard: list.flatMap { saved("identifier", of: $0) },
            displayOrderInPinboard: saved("displayOrderInPinboard", of: item) ?? 0
        )
    }

    private static func deletedItem(_ item: ItemEntity) -> ItemChangeReversal.DeletedItem? {
        guard let identifier: String = saved("identifier", of: item),
              let checksum: String = saved("checksum", of: item),
              let createdAt: Date = saved("createdAt", of: item)
        else { return nil }
        let data: ItemDataEntity? = saved("data", of: item)
        let application: ApplicationEntity? = saved("sourceApplication", of: item)
        let device: DeviceEntity? = saved("device", of: item)
        return ItemChangeReversal.DeletedItem(
            identifier: identifier,
            checksum: checksum,
            rawType: saved("rawType", of: item) ?? 0,
            rawPreview: saved("rawPreview", of: item),
            rawPasteboardItems: data.flatMap { saved("rawPasteboardItems", of: $0) } ?? Data(),
            createdAt: createdAt,
            updatedAt: saved("updatedAt", of: item),
            placement: savedPlacement(of: item),
            sourceApplicationBundleIdentifier: application.flatMap { saved("bundleIdentifier", of: $0) },
            deviceIdentifier: device.flatMap { saved("identifier", of: $0) }
        )
    }
}

// MARK: - Applying

extension WritingContext {
    /// Puts the items back as `reversal` remembers them. What can no longer be put back is
    /// skipped: an item that is gone stays gone, and a pinboard that was deleted in the
    /// meantime is not brought back for its items.
    public func apply(_ reversal: ItemChangeReversal) throws {
        try items(reversal.inserted.map(ItemID.init)).forEach(context.delete)
        for record in reversal.deleted {
            try recreate(record)
        }
        for (identifier, values) in reversal.changed {
            guard let item = try context.first(ItemEntity.self, where: "identifier", equals: identifier) else { continue }
            try put(values, back: item)
        }
    }

    private func recreate(_ record: ItemChangeReversal.DeletedItem) throws {
        guard try context.first(ItemEntity.self, where: "identifier", equals: record.identifier) == nil else { return }
        let pinboard = try record.placement.pinboard.flatMap {
            try context.first(ListEntity.self, where: "identifier", equals: $0)
        }
        // With its pinboard gone and no place in the history there is nowhere to put it.
        guard record.placement.timestamp != nil || pinboard != nil else { return }

        let item = ItemEntity(context: context)
        item.identifier = record.identifier
        item.checksum = record.checksum
        item.rawType = record.rawType
        item.rawPreview = record.rawPreview
        item.createdAt = record.createdAt
        item.updatedAt = record.updatedAt
        item.title = record.placement.title
        item.timestamp = record.placement.timestamp
        item.list = pinboard
        item.displayOrderInPinboard = record.placement.displayOrderInPinboard
        item.setOrigin(
            device: try record.deviceIdentifier.flatMap {
                try context.first(DeviceEntity.self, where: "identifier", equals: $0)
            },
            sourceApplication: try record.sourceApplicationBundleIdentifier.flatMap {
                try context.first(ApplicationEntity.self, where: "bundleIdentifier", equals: $0)
            }
        )

        let data = ItemDataEntity(context: context)
        data.rawPasteboardItems = record.rawPasteboardItems
        item.data = data
    }

    /// Puts back the values a transaction changed, and only those: anything else that has
    /// happened to the item since stays. A pinboard deleted in the meantime is not brought back,
    /// and the item is not taken off the one it is on now. An item that ends up neither in the
    /// history nor on a pinboard is deleted, as removing it from its last list does.
    ///
    /// Writes only what differs: Core Data marks an object as changed even when a setter
    /// receives the value it already has.
    private func put(_ values: [ItemChangeReversal.PlacementValue], back item: ItemEntity) throws {
        var changed = false
        for value in values {
            switch value {
            case .title(let title):
                guard item.title != title else { continue }
                item.title = title
            case .timestamp(let timestamp):
                guard item.timestamp != timestamp else { continue }
                item.timestamp = timestamp
            case .pinboard(let identifier):
                let pinboard: ListEntity?
                if let identifier {
                    guard let existing = try context.first(ListEntity.self, where: "identifier", equals: identifier) else { continue }
                    pinboard = existing
                } else {
                    pinboard = nil
                }
                guard item.list !== pinboard else { continue }
                item.list = pinboard
            case .displayOrderInPinboard(let order):
                guard item.displayOrderInPinboard != order else { continue }
                item.displayOrderInPinboard = order
            }
            changed = true
        }
        if changed {
            item.updatedAt = now
            deleteIfNowhere(item)
        }
    }
}
