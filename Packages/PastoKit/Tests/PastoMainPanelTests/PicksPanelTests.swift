import CoreGraphics
import PastoCoreUI
import PastoPicks
import QuartzCore
import Testing
@testable import PastoMainPanel

/// The suggestions mode's wave, button animation, placeholder layout and paste sources.
@Suite struct PicksPanelTests {
    // MARK: - Wave

    @Test func distancesAreRelativeToTheFarthestCard() {
        let distances = StripWave.relativeDistances(
            of: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 40), CGPoint(x: 100, y: 0)],
            from: .zero,
            emptyExtent: 500
        )
        #expect(distances == [0, 0.5, 1])
    }

    @Test func withNoCardsThereIsNothingToMeasure() {
        #expect(StripWave.relativeDistances(of: [], from: .zero, emptyExtent: 500).isEmpty)
        #expect(StripWave.relativeDistances(of: [.zero], from: .zero, emptyExtent: 500) == [0])
    }

    @Test func revealingRunsAtFullLengthAndHidingAtThreeQuarters() {
        let reveal = StripWave.timing(distance: 1, reveal: true)
        #expect(abs(reveal.delay - 0.4074) < 1e-9)
        #expect(abs(reveal.fadeDuration - 0.2716) < 1e-9)
        #expect(abs(reveal.rippleDuration - 0.5432) < 1e-9)

        let hide = StripWave.timing(distance: 0.5, reveal: false)
        #expect(abs(hide.delay - 0.4074 * 0.5 * 0.75) < 1e-9)
        #expect(abs(hide.fadeDuration - 0.2716 * 0.75) < 1e-9)
        #expect(StripWave.timing(distance: 0, reveal: false).delay == 0)
    }

    @Test func theRippleStartsAndEndsAtRestAndWeakensWithDistance() {
        let size = CGSize(width: 200, height: 200)
        let near = StripWave.rippleKeyframes(distance: 0, size: size)
        let far = StripWave.rippleKeyframes(distance: 1, size: size)
        #expect(near.count == 4)
        #expect(CATransform3DIsIdentity(near[0]))
        #expect(CATransform3DIsIdentity(near[3]))
        // The card moves less far from the button.
        let anchor = CGPoint.zero
        #expect(abs(project(anchor, near[1]).y) > abs(project(anchor, far[1]).y))
        // Its anchor moves by 3 % of its height, downwards in a layer whose y points up, and
        // then up by 1 %.
        #expect(abs(project(anchor, near[1]).y - -6) < 1e-6)
        #expect(abs(project(anchor, near[2]).y - 2) < 1e-6)
        // The growth is about the anchor: the opposite corner moves out.
        #expect(project(CGPoint(x: 200, y: 0), near[1]).x > 200)
    }

    @Test func theRippleIsBuiltLikeCoreAnimationsCallsOnAPerspective() {
        let size = CGSize(width: 120, height: 100)
        let frames = StripWave.rippleKeyframes(distance: 0.5, size: size)
        let s: CGFloat = 1 - 0.55 * 0.5
        var p = CATransform3DIdentity
        p.m34 = -1 / (5 * 100)
        var expected = CATransform3DTranslate(p, 0, -0.03 * 100 * s, 0)
        expected = CATransform3DRotate(expected, 0.16 * s, 1, 0, 0)
        expected = CATransform3DScale(expected, 1 + 0.02 * s, 1 + 0.02 * s, 1)
        #expect(CATransform3DEqualToTransform(frames[1], expected))
        #expect(frames[1].m34 != 0)
    }

    // MARK: - Button

    @Test func theButtonScalesAboutItsCentre() {
        let transform = SuggestionsButtonAnimation.scale(0.2, aboutCenterOf: CGSize(width: 32, height: 32))
        let center = project(CGPoint(x: 16, y: 16), transform)
        let corner = project(.zero, transform)
        #expect(abs(center.x - 16) < 1e-6 && abs(center.y - 16) < 1e-6)
        #expect(abs(corner.x - 12.8) < 1e-6 && abs(corner.y - 12.8) < 1e-6)
    }

    // MARK: - Placeholder

    @Test func theAccessBlockIsACentredColumnAboveTheMiddle() {
        let sizes = PicksPlaceholderLayout.Sizes(
            icon: CGSize(width: 36, height: 36),
            title: CGSize(width: 300, height: 20),
            subtitle: CGSize(width: 460, height: 32),
            primaryButton: CGSize(width: 180, height: 30),
            secondaryButton: CGSize(width: 70, height: 20)
        )
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 248)
        let layout = PicksPlaceholderLayout(sizes: sizes, in: bounds)

        // 36 + 10 + 20 + 6 + 32 + 10 + 30 = 144 tall, centred 17 pt above the middle (124 + 17).
        #expect(layout.icon.maxY == 213)
        #expect(layout.primaryButton.minY == 69)
        #expect(layout.icon.midX == 500)
        #expect(layout.subtitle.midX == 500)
        #expect(layout.title.maxY == layout.icon.minY - 10)
        #expect(layout.subtitle.maxY == layout.title.minY - 6)
        #expect(layout.primaryButton.maxY == layout.subtitle.minY - 10)
        // The buttons sit side by side, 10 pt apart, centred as a pair and on each other.
        #expect(layout.secondaryButton.minX - layout.primaryButton.maxX == 10)
        #expect(layout.primaryButton.minX == 370)
        #expect(layout.secondaryButton.midY == layout.primaryButton.midY)
    }

    // MARK: - Paste sources

    @Test func pastesAreTracedToWhatTheStripShowed() {
        #expect(ChoiceSource(.picks) == .strip)
        #expect(ChoiceSource(.search) == .search)
        #expect(ChoiceSource(.history) == .list)
        #expect(ChoiceSource(.pinboard) == .list)
    }

    /// Where `transform` takes `point`, perspective included.
    private func project(_ point: CGPoint, _ transform: CATransform3D) -> CGPoint {
        let x = point.x * transform.m11 + point.y * transform.m21 + transform.m41
        let y = point.x * transform.m12 + point.y * transform.m22 + transform.m42
        let w = point.x * transform.m14 + point.y * transform.m24 + transform.m44
        return CGPoint(x: x / w, y: y / w)
    }
}
