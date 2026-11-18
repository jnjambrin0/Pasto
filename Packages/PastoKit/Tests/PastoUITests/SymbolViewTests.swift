import CoreGraphics
import Testing
@testable import PastoUI

/// The alignment rects are the system's for each symbol at the size the toolbar uses; the
/// expected origins centre each glyph's alignment rect on the pixel grid of a 2x screen.
@Suite struct SymbolViewTests {
    private func origin(in side: CGFloat, alignmentRect: CGRect, scale: CGFloat = 2) -> CGPoint {
        SymbolView.imageOrigin(
            boundsSize: CGSize(width: side, height: side),
            alignmentRect: alignmentRect,
            scale: scale
        )
    }

    @Test func centresTheAlignmentRectNotTheImage() {
        // Magnifying glass, 21 × 20: centring the image would put it at (5.5, 6).
        #expect(origin(in: 32, alignmentRect: CGRect(x: 0, y: 3.5, width: 20.5, height: 12)) == CGPoint(x: 6, y: 6.5))
        // Ellipsis, 19 × 7: its alignment rect starts below the image.
        #expect(origin(in: 32, alignmentRect: CGRect(x: 0, y: -3, width: 18.5, height: 12)) == CGPoint(x: 7, y: 13))
    }

    @Test func keepsHalfPointsOnA2xScreen() {
        // Plus, 18 × 17.
        #expect(origin(in: 32, alignmentRect: CGRect(x: 0, y: 2.5, width: 18, height: 12)) == CGPoint(x: 7, y: 7.5))
    }

    @Test func halfPixelsRoundToTheEvenPixel() {
        // History clock, 16 × 15, in its 18 pt slot: 1.25 pt is 2.5 px, which goes down to 2 px,
        // while the 11.5 px and 13.5 px of the glyphs above go up to 12 and 14.
        #expect(origin(in: 18, alignmentRect: CGRect(x: 0, y: 3, width: 15.5, height: 9)) == CGPoint(x: 1, y: 1.5))
    }

    @Test func snapsToWholePointsOnA1xScreen() {
        let magnifier = CGRect(x: 0, y: 3.5, width: 20.5, height: 12)
        #expect(origin(in: 32, alignmentRect: magnifier, scale: 1) == CGPoint(x: 6, y: 6))
    }
}
