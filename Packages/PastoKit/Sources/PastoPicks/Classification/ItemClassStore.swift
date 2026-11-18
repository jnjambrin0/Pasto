import Foundation
import os
import PastoCore
import PastoFoundation

/// The class of each item.
///
/// Two sources: what the rules said, kept in memory only because it is cheap to work out again,
/// and what the language model answered, kept on disk so that it is never asked twice about an
/// item. An item has a class once the rules have been applied to it in this run; the model's
/// newest answer then takes their place, unless the rules found a secret. Nothing of the items'
/// content is stored.
actor ItemClassStore {
    /// One answer of the language model, as the file keeps it.
    struct Record: Sendable, Codable, Hashable {
        var itemIdentifier: ItemID
        var itemClass: ItemClass
        var classifiedAt: Date
    }

    private let file: JSONLinesLog<Record>
    private let now: @Sendable () -> Date
    private let log = Log.logger(.picks)
    private var ruleClasses: [ItemID: ItemClass] = [:]
    /// The file's records, read the first time they are needed; the last one for an item wins.
    private var loadedRecords: [ItemID: ItemClass]?

    /// - Parameter capacity: How many records the file keeps, the newest ones.
    init(url: URL, capacity: Int = PicksMetrics.classStoreCapacity, now: @escaping @Sendable () -> Date = { Date() }) {
        file = JSONLinesLog(url: url, limit: .count(capacity), now: now)
        self.now = now
    }

    /// The item's class, or `nil` if the rules have not been applied to it in this run.
    func itemClass(of item: ItemID) async -> ItemClass? {
        guard let ruleClass = ruleClasses[item] else { return nil }
        return await combined(ruleClass, for: item)
    }

    /// Whether the language model has already classified the item.
    func hasModelClass(for item: ItemID) async -> Bool {
        await records()[item] != nil
    }

    /// Keeps what the rules said about the item and returns its class.
    @discardableResult
    func setRuleClass(_ itemClass: ItemClass, for item: ItemID) async -> ItemClass {
        ruleClasses[item] = itemClass
        return await combined(itemClass, for: item)
    }

    /// Keeps the language model's answer — `unclassified` included, so that the item is not
    /// asked about again.
    func setModelClass(_ itemClass: ItemClass, for item: ItemID) async throws {
        try await file.append(Record(itemIdentifier: item, itemClass: itemClass, classifiedAt: now()))
        var records = await records()
        records[item] = itemClass
        loadedRecords = records
    }

    /// Forgets every class and deletes the file.
    func erase() async throws {
        ruleClasses = [:]
        loadedRecords = [:]
        try await file.erase()
    }

    /// A secret found by the rules stands; otherwise the model's answer, if it gave one.
    private func combined(_ ruleClass: ItemClass, for item: ItemID) async -> ItemClass {
        guard ruleClass != .secret else { return .secret }
        return await records()[item] ?? ruleClass
    }

    private func records() async -> [ItemID: ItemClass] {
        if let loadedRecords { return loadedRecords }
        let entries: [Record]
        do {
            entries = try await file.entries()
        } catch {
            log.error("Could not read the item classes: \(error)")
            entries = []
        }
        let records = Dictionary(entries.map { ($0.itemIdentifier, $0.itemClass) }, uniquingKeysWith: { _, last in last })
        loadedRecords = records
        return records
    }
}
