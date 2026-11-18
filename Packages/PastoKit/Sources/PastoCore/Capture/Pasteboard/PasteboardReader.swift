import Foundation
import os
import PastoFoundation

/// One read of the pasteboard, in this order: privacy gate, items, capture decision and only then
/// the data, so that a change the rules veto never has its data fetched.
struct PasteboardReader {
    enum Outcome: Equatable {
        /// The user has not allowed Pasto to read the pasteboard; nothing was touched.
        case accessNeeded
        /// The pasteboard did not hand over its items.
        case unreadable
        /// The capture rules vetoed the change; no data was fetched.
        case skipped(CaptureRules.SkipReason)
        /// What was read. `pasteboardWasEmpty`: the pasteboard had no items at all, as opposed to
        /// items that ended up with nothing worth keeping.
        case read(items: [PasteboardItemSnapshot], pasteboardWasEmpty: Bool)
    }

    /// The most bytes one read keeps, over all items and types.
    let maximumSize: Int
    private let log = Log.logger(.pasteboard)

    init(maximumSize: Int) {
        self.maximumSize = maximumSize
    }

    func read(
        _ source: any PasteboardSource,
        frontmostBundleIdentifier: String?,
        rules: CaptureRules
    ) -> Outcome {
        guard source.allowsProgrammaticReads else {
            return .accessNeeded
        }
        guard let sourceItems = source.items() else {
            return .unreadable
        }
        let types = sourceItems.flatMap(\.types)
        log.debug("Retrieved \(types.count) types: \(types.joined(separator: ", "), privacy: .public)")

        let decision = rules.decision(frontmostBundleIdentifier: frontmostBundleIdentifier, types: types) {
            source.string(forType: PasteboardMarker.source)
        }
        if case .skip(let reason) = decision {
            return .skipped(reason)
        }

        let filter = PasteboardTypeFilter(types: types, frontmostBundleIdentifier: frontmostBundleIdentifier)
        var totalSize = 0
        let items = sourceItems.compactMap { snapshot(of: $0, filter: filter, totalSize: &totalSize) }
        return .read(items: items, pasteboardWasEmpty: sourceItems.isEmpty)
    }

    /// Fetches every representation the filter lets through and the size limit has room for.
    /// An item left with none is dropped.
    private func snapshot(
        of item: any PasteboardSourceItem,
        filter: PasteboardTypeFilter,
        totalSize: inout Int
    ) -> PasteboardItemSnapshot? {
        var types: [String] = []
        var dataByType: [String: Data] = [:]
        for type in item.types where filter.shouldRead(type) {
            // Fetching is what forces data that was only promised.
            guard let data = item.data(forType: type) else { continue }
            guard totalSize + data.count <= maximumSize else {
                // Skipped data does not count: something smaller that follows may still fit.
                log.info("Skipped oversized data (\(data.count) bytes) for type \(type, privacy: .public)")
                continue
            }
            totalSize += data.count
            types.append(type)
            dataByType[type] = data
        }
        return types.isEmpty ? nil : PasteboardItemSnapshot(types: types, dataByType: dataByType)
    }
}
