import Foundation
import PastoCore

/// Whether an item has anything to share, which enables the preview's Share button. It follows
/// what sharing the item hands over: the strings of a text or a colour, the address of a link,
/// the image, or the files — and these only while every one of them is still there.
nonisolated enum ShareAvailability {
    /// - Parameters:
    ///   - pasteboardItems: The item's data, read only for the kinds of content shared from it.
    ///   - isReachable: Whether there is still a file at a path.
    static func canShare(
        _ preview: ItemPreview,
        pasteboardItems: @autoclosure () -> [PasteboardItemSnapshot],
        isReachable: (String) -> Bool
    ) -> Bool {
        switch preview {
        case .text, .color: pasteboardItems().contains { $0.plainText != nil }
        case .link: true
        case .image: pasteboardItems().contains { $0.imageData != nil }
        case .files(let files): !files.paths.isEmpty && files.paths.allSatisfy(isReachable)
        case .unknown: false
        }
    }
}
