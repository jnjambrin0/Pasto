import CoreData

/// A clipboard item. Its pasteboard data lives in `ItemDataEntity` so that listing items never loads it.
@objc(PastoItemEntity)
final class ItemEntity: NSManagedObject, ModelEntity {
    static let entityName = "ItemEntity"

    @NSManaged var identifier: String
    @NSManaged var checksum: String
    @NSManaged var rawType: Int64
    @NSManaged var title: String?
    @NSManaged var rawPreview: Data?
    @NSManaged var displayOrderInPinboard: Int64
    /// When the item was last copied or used; `nil` once it has left the history.
    @NSManaged var timestamp: Date?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date?

    /// Required by the model; optional here because a deleted object no longer has it.
    @NSManaged var data: ItemDataEntity?
    /// The pinboard the item is on, if any. Whether it is in the history is `timestamp`'s to say.
    @NSManaged var list: ListEntity?
    @NSManaged var device: DeviceEntity?
    @NSManaged var sourceApplication: ApplicationEntity?
}

extension ItemEntity {
    var type: ItemType {
        get { ItemType(rawValue: rawType) ?? .unknown }
        set { rawType = newValue.rawValue }
    }

    /// `.unknown` when there is no preview or it was written in a format this version cannot read.
    var preview: ItemPreview {
        guard let rawPreview, let preview = try? BinaryPropertyList.decode(ItemPreview.self, from: rawPreview) else {
            return .unknown
        }
        return preview
    }

    func setPreview(_ preview: ItemPreview) throws {
        rawPreview = try BinaryPropertyList.encode(preview)
    }

    /// Sets where an item being inserted comes from, leaving the other side of both
    /// relationships alone: Core Data would load the whole to-many `items` of the device or the
    /// application to add one item to it — for this Mac's device, every item of the store — and
    /// no row stores that side anyway.
    ///
    /// Only for an item that is not saved yet: on a saved one, a change made this way is not
    /// noticed, and so not saved.
    func setOrigin(device: DeviceEntity?, sourceApplication: ApplicationEntity?) {
        precondition(isInserted, "Only an item being inserted takes its origin this way")
        setPrimitiveValue(device, forKey: "device")
        setPrimitiveValue(sourceApplication, forKey: "sourceApplication")
    }
}

extension Item {
    init(_ entity: ItemEntity) {
        self.init(
            id: ItemID(rawValue: entity.identifier),
            type: entity.type,
            title: entity.title,
            preview: entity.preview,
            timestamp: entity.timestamp,
            createdAt: entity.createdAt,
            listID: entity.list.map { ListID(rawValue: $0.identifier) },
            displayOrderInPinboard: entity.displayOrderInPinboard,
            sourceApplication: entity.sourceApplication.map(SourceApplication.init),
            device: entity.device.map(Device.init)
        )
    }
}
