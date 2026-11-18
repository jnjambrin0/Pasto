import PastoCoreUI
import PastoPicks

extension ChoiceSource {
    /// Where an item was chosen, by what the strip was showing.
    init(_ collection: ItemCellContext.Collection) {
        switch collection {
        case .picks: self = .strip
        case .search: self = .search
        case .history, .pinboard: self = .list
        }
    }
}
