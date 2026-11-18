import CoreGraphics
import PastoUI
import Testing
@testable import PastoCoreUI

/// Where a card's content starts in every density, and how the layout moves between densities.
@Suite struct ItemCellLayoutTests {
    @Test func bodyStartsUnderTheHeader() {
        let expected: [(SizeClass, CGFloat)] = [(.large, 56), (.regular, 52), (.small, 48), (.compact, 36)]
        for (sizeClass, height) in expected {
            let layout = ItemCellLayout(sizeClass: sizeClass, isCompactContentFullSize: false)
            #expect(layout.headerHeight == height)
            #expect(layout.contentTopOffset == height)
        }
    }

    @Test func fullSizeContentOnlyReachesTheTopInCompact() {
        let compact = ItemCellLayout(sizeClass: .compact, isCompactContentFullSize: true)
        #expect(compact.contentTopOffset == 0)
        #expect(compact.headerHeight == 36)

        for sizeClass in [SizeClass.large, .regular, .small] {
            #expect(
                ItemCellLayout(sizeClass: sizeClass, isCompactContentFullSize: true)
                    == ItemCellLayout(sizeClass: sizeClass, isCompactContentFullSize: false)
            )
        }
    }

    @Test func transitionIsLinear() {
        let small = ItemCellLayout(sizeClass: .small, isCompactContentFullSize: true)
        let compact = ItemCellLayout(sizeClass: .compact, isCompactContentFullSize: true)

        #expect(ItemCellLayout.blend(from: small, to: compact, progress: 0) == small)
        #expect(ItemCellLayout.blend(from: small, to: compact, progress: 1) == compact)
        #expect(ItemCellLayout.blend(from: small, to: compact, progress: 0.5) == ItemCellLayout(contentTopOffset: 24, headerHeight: 42))
    }

    @Test func approachingClosesInOnTheTargetFromTheCurrentValue() {
        let start: CGFloat = 10
        #expect(start.approaching(0, progress: 0) == 10)
        #expect(start.approaching(0, progress: 0.5) == 5)
        #expect(start.approaching(0, progress: 1) == 0)
        // Applied frame after frame it is not linear in time: two half steps leave a quarter.
        #expect(start.approaching(0, progress: 0.5).approaching(0, progress: 0.5) == 2.5)
    }
}
