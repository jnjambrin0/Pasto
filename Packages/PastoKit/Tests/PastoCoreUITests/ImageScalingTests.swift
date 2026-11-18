import CoreGraphics
import Testing
@testable import PastoCoreUI

/// When an image fills its frame and when it fits inside it, mostly on a 232 × 184 pt card body.
@Suite struct ImageScalingTests {
    static let body = CGSize(width: 232, height: 184)
    static let defaultRatio = AdaptiveScalingImageView.defaultScaleToFillRatio

    func mode(_ width: CGFloat, _ height: CGFloat, in view: CGSize = body, ratio: CGFloat = defaultRatio) -> ImageScaling.Mode {
        ImageScaling.mode(imageSize: CGSize(width: width, height: height), viewSize: view, scaleToFillRatio: ratio)
    }

    func rect(_ width: CGFloat, _ height: CGFloat, in view: CGSize = body, ratio: CGFloat = defaultRatio) -> CGRect {
        ImageScaling.imageRect(imageSize: CGSize(width: width, height: height), viewSize: view, scaleToFillRatio: ratio)
    }

    @Test func similarityIsOneForTheSameShape() {
        #expect(ImageScaling.similarity(imageSize: CGSize(width: 464, height: 368), viewSize: Self.body) == 1)
        let wide = ImageScaling.similarity(imageSize: CGSize(width: 640, height: 400), viewSize: Self.body)
        #expect(abs(wide - 0.788) < 0.001)
        let square = ImageScaling.similarity(imageSize: CGSize(width: 96, height: 96), viewSize: Self.body)
        #expect(abs(square - 0.793) < 0.001)
    }

    @Test func fillsOnlyWithinTwentyPercentOfTheFramesShape() {
        #expect(mode(640, 400) == .fit)
        #expect(mode(96, 96) == .fit)
        #expect(mode(800, 600) == .fill)        // 4:3, similarity 0.946
        #expect(mode(232, 184) == .fill)
        #expect(mode(1600, 200) == .fit)
        #expect(mode(200, 1600) == .fit)
    }

    @Test func thresholdIsInclusive() {
        // An image exactly 20 % narrower than the frame still fills.
        #expect(mode(80, 100, in: CGSize(width: 100, height: 100)) == .fill)
        #expect(mode(79, 100, in: CGSize(width: 100, height: 100)) == .fit)
    }

    @Test func fittedImageIsCentredOnWholePoints() {
        // 640 × 400 scales to 232 × 145 and sits from y = 19 to 165 once rounded outwards.
        #expect(rect(640, 400) == CGRect(x: 0, y: 19, width: 232, height: 146))
    }

    @Test func smallImagesAreEnlarged() {
        #expect(rect(96, 96) == CGRect(x: 24, y: 0, width: 184, height: 184))
    }

    @Test func filledImageCoversTheFrameAndOverflowsOnOneAxis() {
        // 4:3 is wider than the frame: it takes the height and overflows sideways.
        #expect(rect(800, 600) == CGRect(x: -7, y: 0, width: 246, height: 184))
        // 300 × 260 is narrower: it takes the width and overflows vertically.
        #expect(rect(300, 260) == CGRect(x: 0, y: -9, width: 232, height: 202))
    }

    @Test func linkPreviewsFillMoreReadilyAndAlwaysInCompact() {
        let preview = CGSize(width: 232, height: 130)
        // A 1200 × 630 page image against a 232 × 130 area: similarity 0.937.
        #expect(mode(1200, 630, in: preview, ratio: LinkCellMetrics.scaleToFillRatio) == .fill)
        // 0.75 would not fill an image card but fills a link preview.
        #expect(mode(174, 130, in: preview, ratio: LinkCellMetrics.scaleToFillRatio) == .fill)
        #expect(mode(174, 130, in: preview) == .fit)
        // Ratio 0, as in the compact density: everything fills.
        #expect(mode(100, 1000, in: preview, ratio: 0) == .fill)
    }

    @Test func emptySizesGiveNoRect() {
        #expect(rect(0, 0) == .zero)
        #expect(rect(10, 10, in: .zero) == .zero)
    }
}
