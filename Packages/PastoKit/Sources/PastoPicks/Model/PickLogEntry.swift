import Foundation
import PastoCore

/// One time suggestions were ranked, for diagnosis: the context, every candidate with its
/// features, what was shown and what the user pasted. The ranking never reads it back.
struct PickLogEntry: Sendable, Hashable, Codable {
    var openedAt: Date
    var context: DestinationContext
    var candidates: [CandidateFeatures]
    var shown: [ItemID]
    var chosen: ItemID?
    var chosenFrom: ChoiceSource?
}
