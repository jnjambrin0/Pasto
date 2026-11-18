import CoreData

/// An application items were copied from; one row per bundle identifier.
@objc(PastoApplicationEntity)
final class ApplicationEntity: NSManagedObject, ModelEntity {
    static let entityName = "ApplicationEntity"

    @NSManaged var bundleIdentifier: String
    @NSManaged var name: String
    @NSManaged var rawColor: Int64
    @NSManaged var rawIcon: Data?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date?

    @NSManaged var items: Set<ItemEntity>
}

extension SourceApplication {
    init(_ entity: ApplicationEntity) {
        self.init(
            bundleIdentifier: entity.bundleIdentifier,
            name: entity.name,
            colorCode: entity.rawColor,
            iconData: entity.rawIcon
        )
    }
}
