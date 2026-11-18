import CoreData
import Foundation

// MARK: - Welcome content

extension WritingContext {
    /// Stores the welcome content — notes in the history, a pinboard of notes and links — unless
    /// the store already has a pinboard, which means it is not new. All of it in this
    /// transaction, so a launch cut short leaves either everything or nothing.
    ///
    /// Membership follows the model (`ItemListQuery`): the history's notes get a `timestamp` and
    /// no list; the pinboard's items get the list and no `timestamp`, so each lives in one place
    /// only. The items are new ones, made on this device and credited to `content.application`,
    /// even when the store holds the same content already.
    ///
    /// - Returns: Whether the content was stored.
    public func seedWelcomeContent(_ content: WelcomeContent) throws -> Bool {
        let pinboards = ListEntity.makeRequest(NSPredicate(format: "rawType == %lld", ListType.pinboard.rawValue))
        pinboards.fetchLimit = 1
        guard try context.count(for: pinboards) == 0 else { return false }

        let source = try content.application.flatMap { application in
            try application.bundleIdentifier.flatMap { bundleIdentifier in
                SourceApplicationResolver.sourceApplication(
                    for: application,
                    stored: try sourceApplication(bundleIdentifier: bundleIdentifier)
                )
            }
        }
        let applicationEntity = try source.map(upserted)
        let linkIcon = content.application?.icon.flatMap(ApplicationIcon.pngData)

        // The first note is the newest; the others a millisecond older each, so that the order
        // does not fall to the identifiers. None is later than the transaction.
        for (offset, entry) in content.historyEntries.enumerated() {
            guard let item = newItem(for: entry, linkIcon: linkIcon) else { continue }
            let timestamp = now.addingTimeInterval(-Double(offset) * Self.welcomeNoteSpacing)
            _ = try inserted(item, timestamp: timestamp, sourceApplication: applicationEntity)
        }

        let pinboard = try self.pinboard(createPinboard(name: content.pinboardName, color: content.pinboardColor))
        for entry in content.pinboardEntries {
            guard let item = newItem(for: entry, linkIcon: linkIcon) else { continue }
            let entity = try inserted(item, timestamp: nil, sourceApplication: applicationEntity)
            entity.displayOrderInPinboard = nextDisplayOrder(in: pinboard)
            entity.list = pinboard
        }
        return true
    }

    /// How far apart in time the history's notes are.
    private static let welcomeNoteSpacing: TimeInterval = 0.001

    /// The item an entry stands for, with the representations a copy of it would have: the text;
    /// or the address as text and as URL, with the page's title as the URL's name. Its checksum
    /// is the one a copy would get, so copying the same content later finds this item. `nil` for
    /// an empty note, which capture would not store either.
    private func newItem(for entry: WelcomeContent.Entry, linkIcon: Data?) -> NewItem? {
        switch entry {
        case .note(let title, let text):
            let snapshot = PasteboardItemSnapshot(
                types: [PasteboardType.utf8PlainText],
                dataByType: [PasteboardType.utf8PlainText: Data(text.utf8)]
            )
            let reading = CaptureReading([snapshot])
            guard let checksum = ItemChecksum.checksum(of: reading, type: .text) else { return nil }
            return NewItem(
                type: .text,
                checksum: checksum,
                preview: ItemPreviewBuilder.immediatePreview(of: reading, type: .text),
                pasteboardItems: [snapshot],
                title: title,
                timestamp: now
            )
        case .link(let title, let url, let pageTitle):
            let address = Data(url.absoluteString.utf8)
            let snapshot = PasteboardItemSnapshot(
                types: [PasteboardType.utf8PlainText, PasteboardType.url, PasteboardType.urlName],
                dataByType: [
                    PasteboardType.utf8PlainText: address,
                    PasteboardType.url: address,
                    PasteboardType.urlName: Data(pageTitle.utf8),
                ]
            )
            guard let checksum = ItemChecksum.checksum(of: CaptureReading([snapshot]), type: .link) else { return nil }
            return NewItem(
                type: .link,
                checksum: checksum,
                preview: .link(LinkPreview(url: url, title: pageTitle, iconData: linkIcon)),
                pasteboardItems: [snapshot],
                title: title,
                timestamp: now
            )
        }
    }
}
