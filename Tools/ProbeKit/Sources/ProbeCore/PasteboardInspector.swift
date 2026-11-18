import AppKit
import UniformTypeIdentifiers

/// What a pasteboard holds at one moment: its items and, per item, each type with its size.
public struct PasteboardSnapshot: Codable, Sendable {
    public struct TypeEntry: Codable, Sendable {
        public let type: String
        /// Nil when the data was not read (see `PasteboardInspector.snapshot`).
        public let bytes: Int?
        /// First characters of a textual type, only when content was requested.
        public let preview: String?
    }

    public struct Item: Codable, Sendable {
        public let types: [TypeEntry]
    }

    public let changeCount: Int
    public let accessBehavior: String
    public let items: [Item]

    /// Plain JSON objects, for embedding in an event log line.
    public var itemsAsJSONObject: [[String: Any]] {
        items.map { item in
            ["types": item.types.map { entry in
                var object: [String: Any] = ["type": entry.type]
                if let bytes = entry.bytes { object["bytes"] = bytes }
                return object
            }]
        }
    }
}

@MainActor
public enum PasteboardInspector {
    public static let previewLength = 200

    /// Describes the pasteboard. Listing types never needs permission; `readData` fetches every
    /// representation to measure it, which is what can trigger the system paste prompt and what
    /// forces lazily promised data to be produced.
    public static func snapshot(
        of pasteboard: NSPasteboard = .general, readData: Bool = true, includeContent: Bool = false
    ) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            PasteboardSnapshot.Item(types: item.types.map { type in
                let data = readData ? item.data(forType: type) : nil
                let preview = includeContent && isTextual(type)
                    ? item.string(forType: type).map { String($0.prefix(previewLength)) }
                    : nil
                return .init(type: type.rawValue, bytes: data?.count, preview: preview)
            })
        }
        return PasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            accessBehavior: Permissions.pasteboardAccessName(pasteboard.accessBehavior),
            items: items
        )
    }

    private static func isTextual(_ type: NSPasteboard.PasteboardType) -> Bool {
        guard let contentType = UTType(type.rawValue) else { return false }
        return contentType.conforms(to: .text) || contentType.conforms(to: .url)
    }
}
