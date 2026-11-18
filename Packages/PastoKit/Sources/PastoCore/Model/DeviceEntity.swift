import CoreData

/// A device that copied items: this Mac, or another one that reached the store through sync.
@objc(PastoDeviceEntity)
final class DeviceEntity: NSManagedObject, ModelEntity {
    static let entityName = "DeviceEntity"

    @NSManaged var identifier: String
    @NSManaged var name: String
    @NSManaged var rawType: Int64
    @NSManaged var appVersion: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date?

    @NSManaged var items: Set<ItemEntity>
}

extension DeviceEntity {
    var type: DeviceType {
        get { DeviceType(rawValue: rawType) ?? .mac }
        set { rawType = newValue.rawValue }
    }
}

extension Device {
    init(_ entity: DeviceEntity) {
        self.init(
            identifier: entity.identifier,
            name: entity.name,
            type: entity.type,
            appVersion: entity.appVersion
        )
    }
}
