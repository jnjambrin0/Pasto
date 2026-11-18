import Foundation

/// Turns the items being restored into what is written on the pasteboard.
///
/// A transformation of values: the only step that can have an effect, the processor, is handed in.
struct PasteboardItemComposer {
    /// Whether an image restored on its own also gets a temporary file.
    let includesSingleImageFile: Bool

    /// The pasteboard items to write for `items`, in order.
    ///
    /// - Parameter makeProcessor: Creates the processor of this composition. It is told whether
    ///   every image gets a temporary file, which several items force.
    func compose<Processor: PasteboardItemProcessing>(
        _ items: [RestorableItem],
        options: RestoreOptions,
        makeProcessor: (_ includesSingleImageFile: Bool) -> Processor
    ) -> [PasteboardItemSnapshot] {
        composeByItem(items, options: options, makeProcessor: makeProcessor).flatMap(\.self)
    }

    /// The same composition, with each pasteboard item attributed to the item it comes from:
    /// one list per item of `items`, in order, which is what a drag carries. When several items
    /// with some text become one element, that element belongs to the first item and the others
    /// are left with nothing.
    func composeByItem<Processor: PasteboardItemProcessing>(
        _ items: [RestorableItem],
        options: RestoreOptions,
        makeProcessor: (_ includesSingleImageFile: Bool) -> Processor
    ) -> [[PasteboardItemSnapshot]] {
        let hasSeveralItems = items.count > 1
        let hasText = items.contains { Self.isTextOrLink($0.type) }

        var processor = makeProcessor(includesSingleImageFile || hasSeveralItems)

        // Item by item, the plain-text form or the processor, then sanitizing: neither step looks
        // at another item's elements.
        let elementsByItem = items.map { item in
            let plainTextOption: RestoreOptions = Self.isTextOrLink(item.type) ? .textAsPlainText : .nonTextAsPlainText
            let elements = options.contains(plainTextOption)
                ? item.pasteboardItems.compactMap(\.plainTextForm)
                : processor.process(item)
            return elements.map { sanitized($0, from: item.sourceApplication) }
        }

        // A single item, or several that are all images, files or colors: every element as it is.
        guard hasSeveralItems, hasText else { return elementsByItem }

        // Several items with some text: a paste target takes one piece of text, so the items
        // become one. What has no text is lost.
        let merged = MergedTextElement.make(
            from: elementsByItem.flatMap(\.self),
            asPlainText: options.contains(.textAsPlainText)
        )
        return items.indices.map { index in
            index == 0 ? merged.map { [$0] } ?? [] : []
        }
    }

    private static func isTextOrLink(_ type: ItemType) -> Bool {
        type == .text || type == .link
    }

    /// `element` without the banned types, and signed with the two markers, which go last.
    private func sanitized(_ element: PasteboardItemSnapshot, from source: SourceApplication?) -> PasteboardItemSnapshot {
        var element = element
        element.removeTypes { type in RestoreMetrics.bannedTypes.contains { type.contains($0) } }
        // Whatever the stored item said about its source is replaced by what Pasto knows.
        element.declareLast(PasteboardMarker.source, data: Data((source?.bundleIdentifier ?? "").utf8))
        element.declareLast(PasteboardMarker.ownWrite, data: Data())
        return element
    }
}
