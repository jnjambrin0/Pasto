import Foundation
import PastoCore
import PastoFoundation

/// An empty in-memory store with its reader and its writer, whose clock is fixed.
@MainActor
struct StoreFixture {
    /// What the writer stamps as `createdAt` / `updatedAt`.
    nonisolated static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    let stack: PersistentStack
    let reader: StoreReader
    let writer: StoreWriter

    init() throws {
        stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        reader = StoreReader(stack: stack)
        writer = StoreWriter(stack: stack, now: { StoreFixture.now })
    }

    /// Records one text item per entry, in order, and returns their identifiers.
    func record(_ texts: [String], startingAt second: TimeInterval = 1) async throws -> [ItemID] {
        try await writer.perform(author: .capture) { context in
            try texts.enumerated().map { offset, text in
                try context.record(.text(text, at: second + TimeInterval(offset))).id
            }
        }
    }
}

extension NewItem {
    /// A text item whose checksum is its text.
    static func text(_ text: String, at second: TimeInterval, from application: SourceApplication? = nil) -> NewItem {
        NewItem(
            type: .text,
            checksum: text,
            preview: .text(TextPreview(text: text, characterCount: text.count)),
            pasteboardItems: [
                PasteboardItemSnapshot(
                    types: ["public.utf8-plain-text"],
                    dataByType: ["public.utf8-plain-text": Data(text.utf8)]
                ),
            ],
            sourceApplication: application,
            timestamp: .second(second)
        )
    }
}

extension Date {
    /// Short, readable instants for tests.
    static func second(_ second: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: second)
    }
}
