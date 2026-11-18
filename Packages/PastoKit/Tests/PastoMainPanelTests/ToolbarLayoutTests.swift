import CoreGraphics
import Testing
@testable import PastoMainPanel

/// Frames are in the toolbar's coordinates: window coordinates minus the 8 pt the glass is
/// inset by.
@Suite struct ToolbarLayoutTests {
    private func layout(
        width: CGFloat = 1712,
        tabBarWidth: CGFloat,
        showsSuggestions: Bool = true,
        indicatorsWidth: CGFloat = 0,
        isSearchActive: Bool = false,
        scale: CGFloat = 2
    ) -> ToolbarLayout {
        ToolbarLayout(ToolbarLayout.Input(
            size: CGSize(width: width, height: 60),
            tabBarWidth: tabBarWidth,
            showsSuggestions: showsSuggestions,
            indicatorsWidth: indicatorsWidth,
            isSearchActive: isSearchActive,
            scale: scale
        ))
    }

    private func button(_ x: CGFloat) -> CGRect {
        CGRect(x: x, y: 14, width: 32, height: 32)
    }

    @Test func centresTheTabBarWithTwoTabs() {
        let frames = layout(tabBarWidth: 239)
        #expect(frames.suggestions == button(16))
        #expect(frames.indicators == CGRect(x: 56, y: 0, width: 0, height: 60))
        #expect(frames.search == button(696.5))
        #expect(frames.tabBar == CGRect(x: 736.5, y: 0, width: 239, height: 60))
        #expect(frames.createPinboard == button(983.5))
        #expect(frames.more == button(1664))
        #expect(frames.tabBar.midX == 856)
    }

    @Test func keepsTheTabBarCentredWhenItGrows() {
        let frames = layout(tabBarWidth: 335)
        #expect(frames.search == button(648.5))
        #expect(frames.tabBar == CGRect(x: 688.5, y: 0, width: 335, height: 60))
        #expect(frames.createPinboard == button(1031.5))
    }

    // MARK: Active search

    /// The field takes a quarter of the toolbar, centred: 427 pt in a 1708 pt toolbar. The
    /// collapsed tabs follow it and "+" folds onto their trailing edge.
    @Test func activeSearchFieldIsCentredAtAQuarterOfTheToolbar() {
        let frames = layout(width: 1708, tabBarWidth: 80, isSearchActive: true)
        #expect(frames.search == CGRect(x: 640.5, y: 14, width: 427, height: 32))
        #expect(frames.search.midX == 854)
        #expect(frames.tabBar == CGRect(x: 1075.5, y: 0, width: 80, height: 60))
        #expect(frames.createPinboard.maxX == frames.tabBar.maxX)
        // The fixed ends do not move.
        #expect(frames.suggestions == button(16))
        #expect(frames.more == button(1660))
    }

    @Test func activeSearchFieldIsNeverNarrowerThanItsMinimum() {
        #expect(ToolbarLayout.activeSearchWidth(toolbarWidth: 1200) == 400)
        #expect(ToolbarLayout.activeSearchWidth(toolbarWidth: 1600) == 400)
        #expect(ToolbarLayout.activeSearchWidth(toolbarWidth: 2000) == 500)
        let frames = layout(width: 1200, tabBarWidth: 80, isSearchActive: true)
        #expect(frames.search == CGRect(x: 400, y: 14, width: 400, height: 32))
    }

    @Test func activeSearchFieldSnapsToThePixelGrid() {
        #expect(layout(width: 1201, tabBarWidth: 80, isSearchActive: true, scale: 2).search.minX == 400.5)
        #expect(layout(width: 1201, tabBarWidth: 80, isSearchActive: true, scale: 1).search.minX == 401)
    }

    /// The tabs keep whatever is left up to "…" and scroll; in a toolbar too narrow to centre
    /// the field, the leading limit wins as it does at rest.
    @Test func activeSearchLeavesTheTabsTheRemainingSpace() {
        let wide = layout(width: 1200, tabBarWidth: 500, isSearchActive: true)
        #expect(wide.tabBar == CGRect(x: 808, y: 0, width: 336, height: 60))
        #expect(wide.tabBar.maxX == wide.more.minX - 8)

        let narrow = layout(width: 500, tabBarWidth: 80, isSearchActive: true)
        #expect(narrow.search.minX == 64)
        #expect(narrow.tabBar.width == 0)
    }

    /// With suggestions the leading limit (64) is nearer the centre than the trailing one, so a
    /// wide tab bar is pushed towards "…" first.
    @Test func leadingIndicatorsPushTheGroupTowardsTheTrailingEdge() {
        let frames = layout(width: 1000, tabBarWidth: 796)
        #expect(frames.search == button(64))
        #expect(frames.tabBar == CGRect(x: 104, y: 0, width: 796, height: 60))
        #expect(frames.createPinboard == button(908))
        #expect(frames.createPinboard.maxX <= frames.more.minX - 8)
    }

    @Test func indicatorsMoveTheLeadingLimit() {
        let frames = layout(width: 1000, tabBarWidth: 700, indicatorsWidth: 60)
        #expect(frames.indicators == CGRect(x: 56, y: 0, width: 60, height: 60))
        // Centred, the group would start at 110; the indicators end at 116.
        #expect(frames.search == button(124))
        #expect(frames.tabBar == CGRect(x: 164, y: 0, width: 700, height: 60))
    }

    /// Without suggestions the leading limit drops to 24 and the "…" button is hit first.
    @Test func moreButtonPushesTheGroupTowardsTheLeadingEdge() {
        let frames = layout(width: 1000, tabBarWidth: 820, showsSuggestions: false)
        #expect(frames.suggestions == nil)
        #expect(frames.indicators == CGRect(x: 16, y: 0, width: 0, height: 60))
        #expect(frames.search == button(44))
        #expect(frames.tabBar == CGRect(x: 84, y: 0, width: 820, height: 60))
        #expect(frames.createPinboard == button(912))
        #expect(frames.createPinboard.maxX == frames.more.minX - 8)
    }

    @Test func tabBarYieldsWidthWhenTheGroupDoesNotFit() {
        let frames = layout(width: 1000, tabBarWidth: 1200)
        #expect(frames.search == button(64))
        #expect(frames.tabBar == CGRect(x: 104, y: 0, width: 800, height: 60))
        #expect(frames.createPinboard == button(912))
        #expect(frames.more == button(952))
    }

    @Test func tabBarGetsTheSuggestionsSpaceWhenTheyAreHidden() {
        let frames = layout(width: 1000, tabBarWidth: 1200, showsSuggestions: false)
        #expect(frames.search == button(24))
        #expect(frames.tabBar == CGRect(x: 64, y: 0, width: 840, height: 60))
        #expect(frames.createPinboard == button(912))
    }

    @Test func tabBarWidthNeverGoesNegative() {
        let frames = layout(width: 150, tabBarWidth: 239)
        #expect(frames.tabBar.width == 0)
        // The leading limit wins when nothing fits.
        #expect(frames.search == button(64))
    }

    @Test func centringSnapsToThePixelGrid() {
        #expect(layout(tabBarWidth: 239, scale: 2).tabBar.minX == 736.5)
        #expect(layout(tabBarWidth: 239, scale: 1).tabBar.minX == 737)
        #expect(layout(tabBarWidth: 239, scale: 1).search == button(697))
    }

    @Test func moreMenuIsAskedToOpenAboveTheButtonAndIsConfinedToItsTrailingEdge() {
        #expect(ToolbarLayout.moreMenuOrigin(buttonBounds: CGRect(x: 0, y: 0, width: 32, height: 32)) == CGPoint(x: 0, y: 42))

        // The button's circle spans x 1672…1704 on a screen 1728 wide, 1664…1696 in the toolbar
        // (which starts 8 pt in), and the menu's trailing edge is at 1696.
        let confinement = ToolbarLayout.moreMenuConfinement(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            moreButtonFrame: layout(tabBarWidth: 239).more
        )
        #expect(confinement == CGRect(x: 0, y: 0, width: 1696, height: 1117))

        // On a screen that does not start at the origin, the width is still the button's edge.
        let secondary = ToolbarLayout.moreMenuConfinement(
            screenFrame: CGRect(x: 1728, y: -200, width: 1920, height: 1080),
            moreButtonFrame: CGRect(x: 1856, y: 14, width: 32, height: 32)
        )
        #expect(secondary == CGRect(x: 1728, y: -200, width: 1888, height: 1080))
    }
}
