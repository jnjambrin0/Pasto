import CoreData

/// An entity of the store's model that has its own class.
protocol ModelEntity: NSManagedObject {
    /// The entity's name in the model. The class name differs: it carries the `Pasto` prefix so it
    /// cannot collide in the Objective-C runtime.
    static var entityName: String { get }
}

extension ModelEntity {
    static func makeRequest(_ predicate: NSPredicate? = nil) -> NSFetchRequest<Self> {
        let request = NSFetchRequest<Self>(entityName: entityName)
        request.predicate = predicate
        return request
    }
}

extension NSManagedObjectContext {
    /// The object whose string attribute `key` equals `value`; for the attributes the model declares unique.
    func first<Entity: ModelEntity>(_ entity: Entity.Type, where key: String, equals value: String) throws -> Entity? {
        let request = Entity.makeRequest(NSPredicate(format: "%K == %@", key, value))
        request.fetchLimit = 1
        return try fetch(request).first
    }
}
