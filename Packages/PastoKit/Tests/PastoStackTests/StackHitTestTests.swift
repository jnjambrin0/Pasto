import CoreGraphics
import Foundation
import Testing
@testable import PastoStack

/// A panel of 240 × 300 inside its 24-point margin. The list fills it and its rows start under
/// the 52-point header, at y = 76.
@Suite struct StackHitTestTests {
    private let visibleRow = UUID()
    private let scrolledRow = UUID()
    private let hitTest: StackHitTest

    init() {
        hitTest = StackHitTest(
            panelFrame: CGRect(x: 24, y: 24, width: 240, height: 300),
            listFrame: CGRect(x: 24, y: 24, width: 240, height: 300),
            cardFrames: [
                // Scrolled half-way under the header.
                scrolledRow: CGRect(x: 40, y: 46, width: 208, height: 60),
                visibleRow: CGRect(x: 40, y: 114, width: 208, height: 60),
            ]
        )
    }

    @Test func theRoundedCornersAreOutsideThePanel() {
        #expect(!hitTest.isInsidePanel(CGPoint(x: 26, y: 26)))
        #expect(hitTest.isInsidePanel(CGPoint(x: 50, y: 26)))
        #expect(!hitTest.isInsidePanel(CGPoint(x: 10, y: 100)))
    }

    @Test func aPanelShorterThanItsCornersIsStillAValidShape() {
        var short = hitTest
        short.panelFrame.size.height = 30
        #expect(short.isInsidePanel(CGPoint(x: 144, y: 40)))
    }

    @Test func aRowIsHitOnItsCardBelowTheHeader() {
        #expect(hitTest.row(at: CGPoint(x: 100, y: 130)) == visibleRow)
        #expect(hitTest.row(at: CGPoint(x: 100, y: 90)) == scrolledRow)
        // The part of the card that is under the header.
        #expect(hitTest.row(at: CGPoint(x: 100, y: 60)) == nil)
        // Between two cards.
        #expect(hitTest.row(at: CGPoint(x: 100, y: 110)) == nil)
    }

    @Test func theDeleteButtonCountsAsItsRowEvenWhereItSticksOut() {
        // 4 points to the right of the card and 4 above it.
        #expect(hitTest.row(at: CGPoint(x: 250, y: 112)) == visibleRow)
        #expect(hitTest.row(at: CGPoint(x: 254, y: 112)) == nil)
        #expect(StackHitTest.deleteButtonFrame(forCard: CGRect(x: 40, y: 114, width: 208, height: 60))
            == CGRect(x: 234, y: 110, width: 18, height: 18))
    }

    @Test func theDeleteButtonReachesTwelvePointsIntoTheHeader() {
        var hitTest = hitTest
        hitTest.cardFrames = [scrolledRow: CGRect(x: 40, y: 72, width: 208, height: 60)]
        #expect(hitTest.row(at: CGPoint(x: 245, y: 70)) == scrolledRow)
        hitTest.cardFrames = [scrolledRow: CGRect(x: 40, y: 60, width: 208, height: 60)]
        #expect(hitTest.row(at: CGPoint(x: 245, y: 60)) == nil)
    }

    @Test func aRowIsUnderTheHeaderOnceItsDeleteButtonIs() {
        // The list starts at y = 24, so its rows show from y = 76.
        var hitTest = hitTest
        hitTest.cardFrames = [visibleRow: CGRect(x: 40, y: 80, width: 208, height: 60)]
        #expect(!hitTest.isScrolledUnderHeader(visibleRow))
        hitTest.cardFrames = [visibleRow: CGRect(x: 40, y: 79, width: 208, height: 60)]
        #expect(hitTest.isScrolledUnderHeader(visibleRow))
        #expect(!hitTest.isScrolledUnderHeader(UUID()))
    }

    @Test func pressesAreSortedIntoResizeMoveAndTheRest() {
        // The bottom 8 points of the panel.
        #expect(hitTest.target(at: CGPoint(x: 144, y: 320), isOverControl: false) == .resize)
        #expect(hitTest.target(at: CGPoint(x: 144, y: 315), isOverControl: false) == .move)
        // The header's empty surface, and a button on it.
        #expect(hitTest.target(at: CGPoint(x: 144, y: 50), isOverControl: false) == .move)
        #expect(hitTest.target(at: CGPoint(x: 144, y: 50), isOverControl: true) == .passThrough)
        // A row, and the transparent margin.
        #expect(hitTest.target(at: CGPoint(x: 100, y: 130), isOverControl: false) == .passThrough)
        #expect(hitTest.target(at: CGPoint(x: 10, y: 130), isOverControl: false) == .passThrough)
        #expect(hitTest.target(at: CGPoint(x: 144, y: 330), isOverControl: false) == .passThrough)
    }
}
