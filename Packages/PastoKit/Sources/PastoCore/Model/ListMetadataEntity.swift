import CoreData

/// Where a list sits among the user's lists. Separate from `ListEntity` because the order is
/// private to each user even when the list itself is shared.
@objc(PastoListMetadataEntity)
final class ListMetadataEntity: NSManagedObject, ModelEntity {
    static let entityName = "ListMetadataEntity"

    /// The identifier of the list it belongs to.
    @NSManaged var identifier: String
    @NSManaged var index: Int64
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date?

    @NSManaged var list: ListEntity?
}
