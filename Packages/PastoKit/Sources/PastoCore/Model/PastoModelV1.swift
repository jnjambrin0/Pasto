import CoreData

/// Version 1 of Pasto's store schema, built in code.
///
/// Frozen: stores on disk were created from exactly this description. A schema change is a new
/// builder plus a migration stage, never an edit here; `PastoModelTests` pins what it describes.
/// The current model, `PastoModelV2`, is built from this one.
enum PastoModelV1 {
    /// V1 as the source of the migration to V2, with every entity a plain `NSManagedObject`.
    ///
    /// Core Data binds entity descriptions to their classes globally: a second model whose
    /// entities claimed `ItemEntity` and the rest would make every subclass ambiguous. Class
    /// names are not part of the version hashes, so this is still exactly the V1 the stores on
    /// disk were created from. Immutable from the start, which keeps its version checksum stable
    /// and makes sharing it safe.
    nonisolated(unsafe) static let model: NSManagedObjectModel = {
        let model = makeModel(bindsClasses: false)
        PastoModelV2.freeze(model)
        return model
    }()

    /// - Parameter bindsClasses: Whether the domain entities name their `NSManagedObject`
    ///   subclasses. Only the model the store is opened with may.
    static func makeModel(bindsClasses: Bool) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = domainEntities(bindsClasses: bindsClasses) + syncBookkeepingEntities()
        return model
    }

    private static func domainEntities(bindsClasses: Bool) -> [NSEntityDescription] {
        func entity<Entity: ModelEntity>(for entityClass: Entity.Type, attributes: [NSAttributeDescription]) -> NSEntityDescription {
            let entity = Self.entity(named: Entity.entityName, attributes: attributes)
            if bindsClasses {
                entity.managedObjectClassName = NSStringFromClass(entityClass)
            }
            return entity
        }

        let item = entity(for: ItemEntity.self, attributes: [
            attribute("identifier", .string, preservedInHistoryOnDeletion: true),
            attribute("checksum", .string),
            attribute("rawType", .integer64, default: 0),
            attribute("title", .string, optional: true),
            attribute("rawPreview", .binaryData, optional: true, externalStorage: true),
            attribute("displayOrderInPinboard", .integer64, default: 0),
            attribute("timestamp", .date, optional: true),
            attribute("createdAt", .date),
            attribute("updatedAt", .date, optional: true),
        ])
        let itemData = entity(for: ItemDataEntity.self, attributes: [
            attribute("rawPasteboardItems", .binaryData, externalStorage: true),
        ])
        let list = entity(for: ListEntity.self, attributes: [
            attribute("identifier", .string),
            attribute("name", .string, default: ""),
            attribute("rawType", .integer64, default: 0),
            attribute("rawAttributes", .binaryData, optional: true),
            attribute("rawShareRecord", .binaryData, optional: true),
            attribute("createdAt", .date),
            attribute("updatedAt", .date, optional: true),
        ])
        let listMetadata = entity(for: ListMetadataEntity.self, attributes: [
            attribute("identifier", .string),
            attribute("index", .integer64, default: 0),
            attribute("createdAt", .date),
            attribute("updatedAt", .date, optional: true),
        ])
        let application = entity(for: ApplicationEntity.self, attributes: [
            attribute("bundleIdentifier", .string),
            attribute("name", .string, default: ""),
            attribute("rawColor", .integer64, default: 0),
            attribute("rawIcon", .binaryData, optional: true),
            attribute("createdAt", .date),
            attribute("updatedAt", .date, optional: true),
        ])
        let device = entity(for: DeviceEntity.self, attributes: [
            attribute("identifier", .string),
            attribute("name", .string),
            attribute("rawType", .integer64, default: 0),
            attribute("appVersion", .string, default: ""),
            attribute("createdAt", .date),
            attribute("updatedAt", .date, optional: true),
        ])

        relate(
            End(item, "data", optional: false, deleteRule: .cascadeDeleteRule),
            End(itemData, "item", deleteRule: .nullifyDeleteRule)
        )
        relate(
            End(item, "list", deleteRule: .nullifyDeleteRule),
            End(list, "items", toMany: true, deleteRule: .nullifyDeleteRule)
        )
        relate(
            End(item, "device", deleteRule: .nullifyDeleteRule),
            End(device, "items", toMany: true, deleteRule: .nullifyDeleteRule)
        )
        relate(
            End(item, "sourceApplication", deleteRule: .nullifyDeleteRule),
            End(application, "items", toMany: true, deleteRule: .nullifyDeleteRule)
        )
        relate(
            End(list, "metadata", optional: false, deleteRule: .cascadeDeleteRule),
            End(listMetadata, "list", deleteRule: .denyDeleteRule)
        )

        constrain(item, unique: [["identifier"]], indexes: [("byIdentifier", "identifier"), ("byChecksum", "checksum")])
        constrain(list, unique: [["identifier"]], indexes: [("byIdentifier", "identifier")])
        constrain(listMetadata, indexes: [("byIdentifier", "identifier")])
        constrain(application, unique: [["bundleIdentifier"]], indexes: [("byBundleIdentifier", "bundleIdentifier")])
        constrain(device, unique: [["identifier"]], indexes: [("byIdentifier", "identifier")])

        return [item, itemData, list, listMetadata, application, device]
    }

    /// Defined from the start so that adding sync does not need a migration; nothing reads or
    /// writes them until `PastoSync` does, which is why they have no classes yet.
    private static func syncBookkeepingEntities() -> [NSEntityDescription] {
        let objectMetadata = entity(named: "ObjectMetadata", attributes: [
            attribute("objectURI", .string),
            attribute("cloudKitRecordName", .string),
            attribute("cloudKitZoneName", .string),
            attribute("cloudKitZoneOwnerName", .string),
            attribute("cloudKitRecordData", .binaryData, optional: true),
            attribute("isPendingDeletion", .boolean, default: false),
        ])
        let objectPendingMapping = entity(named: "ObjectPendingMapping", attributes: [
            attribute("objectURI", .string),
            attribute("cloudKitRecordData", .binaryData),
            attribute("pendingMappings", .string),
        ])
        let objectShare = entity(named: "ObjectShare", attributes: [
            attribute("rootRecordName", .string),
            attribute("rootRecordType", .string),
            attribute("shareRecordName", .string),
            attribute("shareRecordOwner", .string),
            attribute("shareRecordData", .binaryData),
        ])

        constrain(
            objectMetadata,
            unique: [["objectURI"], ["cloudKitRecordName", "cloudKitZoneName", "cloudKitZoneOwnerName"]],
            indexes: [("byObjectURI", "objectURI"), ("byCloudKitRecordName", "cloudKitRecordName")]
        )
        constrain(objectPendingMapping, unique: [["objectURI"]], indexes: [("byObjectURI", "objectURI")])
        constrain(
            objectShare,
            unique: [["shareRecordOwner", "shareRecordName"], ["shareRecordOwner", "rootRecordType", "rootRecordName"]],
            indexes: [("byShareRecordName", "shareRecordName"), ("byRootRecordName", "rootRecordName")]
        )

        return [objectMetadata, objectPendingMapping, objectShare]
    }

    // MARK: - Building blocks

    private static func attribute(
        _ name: String,
        _ type: NSAttributeDescription.AttributeType,
        optional: Bool = false,
        default defaultValue: Any? = nil,
        externalStorage: Bool = false,
        preservedInHistoryOnDeletion: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.type = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        attribute.allowsExternalBinaryDataStorage = externalStorage
        attribute.preservesValueInHistoryOnDeletion = preservedInHistoryOnDeletion
        return attribute
    }

    private static func entity(named name: String, attributes: [NSAttributeDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.properties = attributes
        return entity
    }

    /// One side of a relationship.
    private struct End {
        let entity: NSEntityDescription
        let name: String
        let toMany: Bool
        let optional: Bool
        let deleteRule: NSDeleteRule

        init(_ entity: NSEntityDescription, _ name: String, toMany: Bool = false, optional: Bool = true, deleteRule: NSDeleteRule) {
            self.entity = entity
            self.name = name
            self.toMany = toMany
            self.optional = optional
            self.deleteRule = deleteRule
        }

        func relationship(to destination: NSEntityDescription) -> NSRelationshipDescription {
            let relationship = NSRelationshipDescription()
            relationship.name = name
            relationship.destinationEntity = destination
            relationship.isOptional = optional
            relationship.minCount = optional ? 0 : 1
            relationship.maxCount = toMany ? 0 : 1
            relationship.deleteRule = deleteRule
            return relationship
        }
    }

    /// Adds a relationship and its inverse together, so neither can be left without the other.
    private static func relate(_ first: End, _ second: End) {
        let forward = first.relationship(to: second.entity)
        let backward = second.relationship(to: first.entity)
        forward.inverseRelationship = backward
        backward.inverseRelationship = forward
        first.entity.properties.append(forward)
        second.entity.properties.append(backward)
    }

    /// Declares uniqueness constraints and fetch indexes. Has to come after the entity's last
    /// relationship: assigning `properties` silently discards the indexes an entity already had.
    private static func constrain(
        _ entity: NSEntityDescription,
        unique: [[String]] = [],
        indexes: [(name: String, attribute: String)]
    ) {
        entity.uniquenessConstraints = unique
        entity.indexes = indexes.map { index in
            NSFetchIndexDescription(
                name: index.name,
                elements: [NSFetchIndexElementDescription(property: entity.attributesByName[index.attribute]!, collationType: .binary)]
            )
        }
    }
}
