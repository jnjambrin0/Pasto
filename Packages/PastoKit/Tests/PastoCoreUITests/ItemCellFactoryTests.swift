import PastoCore
import Testing
@testable import PastoCoreUI

/// Every item type has a card class of its own.
@Suite struct ItemCellFactoryTests {
    @Test func everyTypeHasItsCard() {
        #expect(ItemCellFactory.cellClass(for: .text) == TextItemCell.self)
        #expect(ItemCellFactory.cellClass(for: .link) == LinkItemCell.self)
        #expect(ItemCellFactory.cellClass(for: .image) == ImageItemCell.self)
        #expect(ItemCellFactory.cellClass(for: .color) == ColorItemCell.self)
        #expect(ItemCellFactory.cellClass(for: .files) == FilesItemCell.self)
        #expect(ItemCellFactory.cellClass(for: .unknown) == UnknownItemCell.self)
    }

    @Test func cardsAreDistinctClasses() {
        let names = Set(ItemType.allCases.map { String(describing: ItemCellFactory.cellClass(for: $0)) })
        #expect(names.count == ItemType.allCases.count)
    }
}
