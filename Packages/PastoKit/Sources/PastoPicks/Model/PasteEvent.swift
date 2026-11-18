import Foundation
import PastoCore

/// One paste, as the paste journal remembers it: which item went from which application to
/// which, and when. Never the item's content.
struct PasteEvent: Sendable, Hashable, Codable {
    var itemIdentifier: ItemID
    var sourceAppBundleIdentifier: String?
    var destinationAppBundleIdentifier: String?
    var timestamp: Date
}
