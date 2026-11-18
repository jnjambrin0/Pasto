import CoreData
import Foundation
import Testing
@testable import PastoCore

struct PastoModelTests {
    private let model = PastoModelV1.model

    /// A store on disk only opens with a model that has exactly these hashes. If this fails, the
    /// schema changed: that calls for a new model version and a migration, not for new values here.
    @Test func versionHashesArePinned() {
        let hashes = model.entityVersionHashesByName.mapValues { hash in
            hash.map { String(format: "%02x", $0) }.joined()
        }

        #expect(hashes == [
            "ApplicationEntity": "317120fa6aff422bdb4432b5ddc239c6764eba5f4f526126646c0147a17bb649",
            "DeviceEntity": "2bf6b2e77de9b3261db81e9f5b73fd687acc42611c61c8fd70fb2f96e3ebb5f3",
            "ItemDataEntity": "48a8fcd216f60580e0fc4e3b2bf0a149ce69e381b2c0587b8ec340e393b2e7d2",
            "ItemEntity": "bc38d01a810b53972d25d75064be15dca8a263d4932e0a721d75a123d5c2ef91",
            "ListEntity": "c582cdf03fb193cdb34de1d35f28f80f1cf9c7e8a1e50ad0c81f8e89ba6f2707",
            "ListMetadataEntity": "292ab3ae53780a568f46ae56f9718995606a275c16ba719ad380848cdbdb9733",
            "ObjectMetadata": "c8b5c43a845aebc450fe7d37a2d6c40543903a67123501e1cd2ad2f09d10f9ef",
            "ObjectPendingMapping": "4d6785bebf0d70e9359689e123e3ae785732e882ef0544846f10a613dea72c86",
            "ObjectShare": "db4c51abf2c1161042b6dd84deb943987a69a5a62ab96eda4a1fab8621130d5d",
        ])
    }

    // The version hashes cover names, types, optionality, uniqueness, external storage and history
    // preservation. Indexes, delete rules and default values are not part of them.

    @Test func uniquenessConstraintsFollowTheSpec() {
        let constraints = Dictionary(uniqueKeysWithValues: model.entities.map { entity in
            (entity.name ?? "", entity.uniquenessConstraints.map { $0.compactMap { $0 as? String } })
        })

        #expect(constraints == [
            "ItemEntity": [["identifier"]],
            "ItemDataEntity": [],
            "ListEntity": [["identifier"]],
            "ListMetadataEntity": [],
            "ApplicationEntity": [["bundleIdentifier"]],
            "DeviceEntity": [["identifier"]],
            "ObjectMetadata": [["objectURI"], ["cloudKitRecordName", "cloudKitZoneName", "cloudKitZoneOwnerName"]],
            "ObjectPendingMapping": [["objectURI"]],
            "ObjectShare": [["shareRecordOwner", "shareRecordName"], ["shareRecordOwner", "rootRecordType", "rootRecordName"]],
        ])
    }

    @Test func indexesFollowTheSpec() {
        let indexes = Dictionary(uniqueKeysWithValues: model.entities.map { ($0.name ?? "", $0.indexes.map(\.name).sorted()) })

        #expect(indexes == [
            "ItemEntity": ["byChecksum", "byIdentifier"],
            "ItemDataEntity": [],
            "ListEntity": ["byIdentifier"],
            "ListMetadataEntity": ["byIdentifier"],
            "ApplicationEntity": ["byBundleIdentifier"],
            "DeviceEntity": ["byIdentifier"],
            "ObjectMetadata": ["byCloudKitRecordName", "byObjectURI"],
            "ObjectPendingMapping": ["byObjectURI"],
            "ObjectShare": ["byRootRecordName", "byShareRecordName"],
        ])
    }

    @Test func deleteRulesFollowTheSpec() {
        let deleteRules = Dictionary(uniqueKeysWithValues: model.entities.flatMap { entity in
            entity.relationshipsByName.map { ("\(entity.name ?? "").\($0.key)", $0.value.deleteRule) }
        })

        #expect(deleteRules == [
            "ItemEntity.data": .cascadeDeleteRule,
            "ItemEntity.list": .nullifyDeleteRule,
            "ItemEntity.device": .nullifyDeleteRule,
            "ItemEntity.sourceApplication": .nullifyDeleteRule,
            "ItemDataEntity.item": .nullifyDeleteRule,
            "ListEntity.items": .nullifyDeleteRule,
            "ListEntity.metadata": .cascadeDeleteRule,
            "ListMetadataEntity.list": .denyDeleteRule,
            "ApplicationEntity.items": .nullifyDeleteRule,
            "DeviceEntity.items": .nullifyDeleteRule,
        ])
    }

    @Test func defaultValuesFollowTheSpec() {
        let defaults = Dictionary(uniqueKeysWithValues: model.entities.flatMap { entity in
            entity.attributesByName.compactMap { name, attribute in
                attribute.defaultValue.map { ("\(entity.name ?? "").\(name)", "\($0)") }
            }
        })

        #expect(defaults == [
            "ItemEntity.rawType": "0",
            "ItemEntity.displayOrderInPinboard": "0",
            "ListEntity.name": "",
            "ListEntity.rawType": "0",
            "ListMetadataEntity.index": "0",
            "ApplicationEntity.name": "",
            "ApplicationEntity.rawColor": "0",
            "DeviceEntity.rawType": "0",
            "DeviceEntity.appVersion": "",
            "ObjectMetadata.isPendingDeletion": "0",
        ])
    }

    // MARK: - Version 2

    private let current = PastoModelV2.model

    private func hex(_ hash: Data?) -> String {
        (hash ?? Data()).map { String(format: "%02x", $0) }.joined()
    }

    /// Only the item's hash moves — through its modifier, since indexes are not hashed — and it is
    /// pinned like V1's.
    @Test func versionTwoChangesOnlyTheItemHash() {
        let v1 = model.entityVersionHashesByName
        let v2 = current.entityVersionHashesByName

        #expect(v2.filter { $0.key != "ItemEntity" } == v1.filter { $0.key != "ItemEntity" })
        #expect(hex(v2["ItemEntity"]) == "c3468067d754423b1e04bb8dbcee4edc6f1fc5b6d78bc9b3d9496fdbb407eac9")
    }

    @Test func versionTwoAddsTheIndexesOfTheListsAndRetention() {
        let indexes = Dictionary(uniqueKeysWithValues: current.entities.map { entity in
            (entity.name ?? "", entity.indexes.map { "\($0.name): \($0.elements.compactMap { $0.property?.name }.joined(separator: ", "))" }.sorted())
        })

        #expect(indexes["ItemEntity"] == [
            "byChecksum: checksum",
            "byIdentifier: identifier",
            "byListAndDisplayOrder: list, displayOrderInPinboard",
            "byListAndTimestamp: list, timestamp",
            "byTimestamp: timestamp, identifier",
        ])
        for entity in model.entities where entity.name != "ItemEntity" {
            #expect(current.entitiesByName[entity.name ?? ""]?.indexes.map(\.name).sorted() == entity.indexes.map(\.name).sorted())
        }
    }

    /// Deleting an item does not reach its device's and application's list of items: that would
    /// load every item of the device on each deletion.
    @Test func versionTwoDoesNotPropagateDeletionsToTheItemsOfADeviceOrApplication() {
        let item = current.entitiesByName["ItemEntity"]!.relationshipsByName
        #expect(item["device"]?.deleteRule == .noActionDeleteRule)
        #expect(item["sourceApplication"]?.deleteRule == .noActionDeleteRule)
        #expect(item["data"]?.deleteRule == .cascadeDeleteRule)
        #expect(item["list"]?.deleteRule == .nullifyDeleteRule)
    }

    @Test func versionTwoKeepsTheRestOfVersionOne() {
        func summary(_ model: NSManagedObjectModel) -> [String] {
            model.entities.flatMap { entity in
                entity.properties.map { property in
                    var line = "\(entity.name ?? "").\(property.name) optional=\(property.isOptional)"
                    if let attribute = property as? NSAttributeDescription {
                        line += " \(attribute.attributeType.rawValue) default=\(String(describing: attribute.defaultValue))"
                    }
                    if let relationship = property as? NSRelationshipDescription {
                        let rule = PastoModelV2.unpropagatedItemRelationships.contains(relationship.name) && entity.name == "ItemEntity"
                            ? "(see above)" : "\(relationship.deleteRule.rawValue)"
                        line += " → \(relationship.destinationEntity?.name ?? "") rule=\(rule)"
                    }
                    return line
                } + ["\(entity.name ?? "") unique=\(entity.uniquenessConstraints)"]
            }.sorted()
        }

        #expect(summary(current) == summary(model))
    }

    /// The classes are bound to the current model only: a second binding would make every
    /// `NSManagedObject` subclass ambiguous.
    @Test func onlyTheCurrentModelNamesTheClasses() {
        #expect(model.entities.allSatisfy { $0.managedObjectClassName == NSStringFromClass(NSManagedObject.self) })
        #expect(current.entitiesByName[ItemEntity.entityName]?.managedObjectClassName == NSStringFromClass(ItemEntity.self))
    }
}
