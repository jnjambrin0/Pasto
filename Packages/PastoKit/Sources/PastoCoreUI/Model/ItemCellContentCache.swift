import AppKit
import PastoCore

/// Keeps the decoded content of the cards recently shown, so that a card coming back into view,
/// or reconfigured after a setting changes, does not parse its rich text, walk its attributes or
/// read its image header again on the main thread.
///
/// It is an `NSCache` of 8 MiB in all, each entry costing twice the bytes it is decoded from,
/// with nothing larger than half of that kept. The key is the preview itself and the appearance
/// the content was worked out in, since a text's dynamic colours are resolved in it.
public final class ItemCellContentCache {
    public static let totalCostLimit = 8 * 1024 * 1024

    private let cache = NSCache<Key, Entry>()

    public init() {
        cache.totalCostLimit = Self.totalCostLimit
    }

    /// The content of a card showing `preview` in `appearance`; `make` builds it when it is not
    /// kept. Only the kinds whose content costs something to build are kept.
    public func content(
        for preview: ItemPreview,
        in appearance: NSAppearance.Name,
        make: () -> ItemCellModel.Content
    ) -> ItemCellModel.Content {
        guard let cost = Self.cost(of: preview) else { return make() }
        let key = Key(preview: preview, appearance: appearance)
        if let entry = cache.object(forKey: key) {
            return entry.content
        }
        let content = make()
        if cost <= Self.totalCostLimit / 2 {
            cache.setObject(Entry(content), forKey: key, cost: cost)
        }
        return content
    }

    public func removeAll() {
        cache.removeAllObjects()
    }

    /// What keeping the content of `preview` costs: twice the bytes it is decoded from. Nil for
    /// the kinds that are not worth keeping, whose content is built from the preview without
    /// decoding anything.
    nonisolated static func cost(of preview: ItemPreview) -> Int? {
        switch preview {
        case .text(let text):
            2 * (text.richTextData?.count ?? text.text.utf8.count)
        case .link(let link):
            2 * (link.url.absoluteString.utf8.count + (link.title?.utf8.count ?? 0)
                + (link.iconData?.count ?? 0) + (link.imageData?.count ?? 0))
        case .image, .color, .files, .unknown:
            nil
        }
    }

    private nonisolated final class Key: NSObject {
        let preview: ItemPreview
        let appearance: NSAppearance.Name

        init(preview: ItemPreview, appearance: NSAppearance.Name) {
            self.preview = preview
            self.appearance = appearance
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(preview)
            hasher.combine(appearance)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return appearance == other.appearance && preview == other.preview
        }
    }

    private nonisolated final class Entry {
        let content: ItemCellModel.Content

        init(_ content: ItemCellModel.Content) {
            self.content = content
        }
    }
}
