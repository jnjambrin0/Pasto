import Foundation

extension PasteboardItemSnapshot {
    /// The item's text as restoring understands it: the first of `RestoreMetrics.stringTypes`
    /// that is present and holds valid UTF-8.
    ///
    /// Not `plainText`: that one serves capture and reads UTF-16 too, which restoring does not.
    var restorableString: String? {
        for type in RestoreMetrics.stringTypes {
            if let data = dataByType[type], let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return nil
    }

    /// The item reduced to its text, as UTF-8 plain text and nothing else; `nil` when it has no
    /// text.
    var plainTextForm: PasteboardItemSnapshot? {
        restorableString.map { string in
            PasteboardItemSnapshot(
                types: [RestoreMetrics.plainTextType],
                dataByType: [RestoreMetrics.plainTextType: Data(string.utf8)]
            )
        }
    }

    /// Declares `type` last, with `data`. An earlier declaration of the type is dropped rather
    /// than left next to the new one: an item must not offer the same type twice.
    mutating func declareLast(_ type: String, data: Data) {
        types.removeAll { $0 == type }
        types.append(type)
        dataByType[type] = data
    }

    /// Removes every type whose identifier satisfies `isRemoved`, with its data.
    mutating func removeTypes(where isRemoved: (String) -> Bool) {
        types.removeAll(where: isRemoved)
        dataByType = dataByType.filter { !isRemoved($0.key) }
    }
}
