import Foundation
import PastoCore

/// Development aid (`--synthetic-items <count>`): fills the store with generated text items so
/// scale and performance can be measured against the real data path.
enum SyntheticItems {
    private static let batchSize = 2_000

    static func insert(_ count: Int, into writer: StoreWriter) async {
        let start = Date()
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            let range = batchStart..<min(batchStart + batchSize, count)
            _ = try? await writer.perform(author: .maintenance) { context in
                for index in range {
                    let text = "Synthetic item #\(index)"
                    let pasteboardItem = PasteboardItemSnapshot(
                        types: ["public.utf8-plain-text"],
                        dataByType: ["public.utf8-plain-text": Data(text.utf8)]
                    )
                    _ = try context.record(NewItem(
                        type: .text,
                        checksum: "synthetic-\(index)",
                        preview: .text(TextPreview(text: text, characterCount: text.count, richTextData: nil)),
                        pasteboardItems: [pasteboardItem],
                        // Item #0 is the newest, so the strip shows them in order.
                        timestamp: start.addingTimeInterval(-Double(index))
                    ))
                }
            }
        }
    }
}
