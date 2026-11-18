import CoreData

/// The clipboard history or a pinboard.
@objc(PastoListEntity)
final class ListEntity: NSManagedObject, ModelEntity {
    static let entityName = "ListEntity"

    @NSManaged var identifier: String
    @NSManaged var name: String
    @NSManaged var rawType: Int64
    @NSManaged var rawAttributes: Data?
    @NSManaged var rawShareRecord: Data?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date?

    /// The items pinned to this list. Always empty for the clipboard history, which is not a
    /// container but the items that have a `timestamp`: see `ItemListQuery`.
    @NSManaged var items: Set<ItemEntity>
    /// Required by the model; optional here because a deleted object no longer has it.
    @NSManaged var metadata: ListMetadataEntity?
}

extension ListEntity {
    var type: ListType {
        // A type from a newer version can only be some kind of user list: the history is unique.
        get { ListType(rawValue: rawType) ?? .pinboard }
        set { rawType = newValue.rawValue }
    }

    /// The type's defaults when nothing is stored or it was written in a format this version cannot read.
    var attributes: ListAttributes {
        guard let rawAttributes,
              let attributes = try? BinaryPropertyList.decode(ListAttributes.self, from: rawAttributes)
        else {
            switch type {
            case .clipboard: return .clipboard(capacity: .month)
            case .pinboard: return .pinboard(color: .gray)
            }
        }
        return attributes
    }

    func setAttributes(_ attributes: ListAttributes) throws {
        rawAttributes = try BinaryPropertyList.encode(attributes)
    }
}

extension ClipList {
    init(_ entity: ListEntity) {
        self.init(
            id: ListID(rawValue: entity.identifier),
            name: entity.name,
            type: entity.type,
            attributes: entity.attributes,
            index: Int(entity.metadata?.index ?? 0),
            isShared: entity.rawShareRecord != nil
        )
    }
}
