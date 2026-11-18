import CoreData

/// Version 2 of Pasto's store schema: V1 plus the fetch indexes that keep the history, the
/// pinboards and retention fast with a year of items.
///
/// Same entities, attributes and relationships as V1, so a V1 store reaches it by a lightweight
/// migration (`StoreMigration`). Frozen like V1: `PastoModelTests` pins what it describes.
enum PastoModelV2 {
    /// The model every store is opened with, and the only model instance of the process whose
    /// entities are bound to their classes (see `PastoModelV1.model`). Immutable from the start.
    nonisolated(unsafe) static let model: NSManagedObjectModel = {
        let model = makeModel()
        freeze(model)
        return model
    }()

    /// What V2 adds to `ItemEntity`: index names and the properties each one covers, in order.
    /// Chosen from the plans SQLite makes for the queries of `ItemListQuery`.
    static let addedItemIndexes: [(name: String, properties: [String])] = [
        // The history (`timestamp != nil`, newest first, ties by identifier) and its newest item
        // on every capture. With the identifier it covers what `ItemCollection` reads of the
        // history: the list is read from the index alone, never from the rows, which carry the
        // previews.
        ("byTimestamp", ["timestamp", "identifier"]),
        // Retention (`list == nil AND timestamp < cutoff`): what a capture lets expire.
        ("byListAndTimestamp", ["list", "timestamp"]),
        // A pinboard (`list == X`), in its order.
        ("byListAndDisplayOrder", ["list", "displayOrderInPinboard"]),
    ]

    /// Relationships whose deletion is not propagated to the other side, by `ItemEntity`
    /// relationship name. Nullifying an item's device or source application means loading every
    /// item of that device or application — the whole history, for this Mac — on each deletion;
    /// the other side is a to-many that no row stores and nothing reads, so there is nothing to
    /// keep in step.
    static let unpropagatedItemRelationships = ["device", "sourceApplication"]

    private static func makeModel() -> NSManagedObjectModel {
        let model = PastoModelV1.makeModel(bindsClasses: true)
        let item = model.entitiesByName[ItemEntity.entityName]!
        // Indexes are not part of an entity's version hash: without a modifier a V1 store would
        // open with this model as it is, and never get them.
        item.versionHashModifier = "2"
        // Delete rules are not part of the version hash either, nor of the schema.
        for name in unpropagatedItemRelationships {
            item.relationshipsByName[name]!.deleteRule = .noActionDeleteRule
        }
        // An index belongs to its entity once set: V1's are described again, not handed back.
        let existing = item.indexes.map { index in (name: index.name, properties: index.elements.compactMap { $0.property?.name }) }
        item.indexes = []
        item.indexes = (existing + addedItemIndexes).map { index in
            NSFetchIndexDescription(
                name: index.name,
                elements: index.properties.map { name in
                    NSFetchIndexElementDescription(property: item.propertiesByName[name]!, collationType: .binary)
                }
            )
        }
        return model
    }

    /// Makes `model` immutable, as handing it to a coordinator does. A model's version checksum,
    /// which migration stages identify it by, is only stable once it is.
    static func freeze(_ model: NSManagedObjectModel) {
        _ = NSPersistentStoreCoordinator(managedObjectModel: model)
    }
}
