import AppKit
import Testing
@testable import PastoPreview

/// Sizes and positions.
@Suite struct PreviewGeometryTests {
    private let screen = CGSize(width: 2000, height: 1000)

    // MARK: Preview size

    @Test func thePreviewAddsItsChromeToTheContent() {
        #expect(PreviewSize.viewSize(contentSize: CGSize(width: 800, height: 600)) == CGSize(width: 810, height: 676))
    }

    @Test func theContentIsNeverSmallerThanItsMinimum() {
        #expect(PreviewSize.viewSize(contentSize: CGSize(width: 20, height: 10)) == CGSize(width: 390, height: 316))
        #expect(PreviewSize.viewSize(contentSize: .zero) == CGSize(width: 390, height: 316))
    }

    @Test func contentWithoutASizeGetsAQuarterOfTheScreen() {
        #expect(PreviewSize.defaultContentSize(screenSize: screen) == CGSize(width: 500, height: 250))
        #expect(PreviewSize.defaultContentSize(screenSize: nil) == .zero)
    }

    @Test func filesGetHalfTheScreen() {
        #expect(PreviewSize.largeContentSize(screenSize: screen) == CGSize(width: 1000, height: 500))
        #expect(PreviewSize.largeContentSize(screenSize: nil) == .zero)
    }

    @Test func aLargeImageIsReducedInProportionToHalfTheScreen() {
        #expect(PreviewSize.imageContentSize(imageSize: CGSize(width: 4000, height: 1000), screenSize: screen)
            == CGSize(width: 1000, height: 250))
        #expect(PreviewSize.imageContentSize(imageSize: CGSize(width: 1000, height: 2000), screenSize: screen)
            == CGSize(width: 250, height: 500))
    }

    @Test func aSmallImageKeepsItsSize() {
        let size = CGSize(width: 64, height: 48)
        #expect(PreviewSize.imageContentSize(imageSize: size, screenSize: screen) == size)
        #expect(PreviewSize.imageContentSize(imageSize: size, screenSize: nil) == size)
    }

    @Test func textTakesWhatItMeasuresPlusTheEditorsInsets() {
        let size = PreviewSize.textContentSize(
            measuredSize: CGSize(width: 300, height: 40), editorInset: CGSize(width: 8, height: 10), screenSize: screen
        )
        #expect(size == CGSize(width: 336, height: 60))
    }

    @Test func textIsBoundedByHalfTheScreenOrAFixedBoxWithoutOne() {
        let inset = CGSize(width: 8, height: 10)
        let huge = CGSize(width: 5000, height: 5000)
        #expect(PreviewSize.textContentSize(measuredSize: huge, editorInset: inset, screenSize: screen)
            == CGSize(width: 1000, height: 500))
        #expect(PreviewSize.textContentSize(measuredSize: huge, editorInset: inset, screenSize: nil)
            == CGSize(width: 1000, height: 1000))
    }

    // MARK: Image zoom

    @Test func aLargeImageOpensFittedAndZoomsToTwiceItsSize() {
        let zoom = ImageMagnification(imageSize: CGSize(width: 4000, height: 2000), viewSize: CGSize(width: 400, height: 400))
        #expect(zoom?.minimum == 1)
        #expect(zoom?.initial == 1)
        #expect(zoom?.maximum == 20)
    }

    @Test func aSmallImageOpensAtItsRealSize() {
        let zoom = ImageMagnification(imageSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 400, height: 400))
        #expect(zoom?.minimum == 0.25)
        #expect(zoom?.initial == 0.25)
        #expect(zoom?.maximum == 0.5)
    }

    @Test func thereIsNoZoomWithoutAnImageOrAView() {
        #expect(ImageMagnification(imageSize: .zero, viewSize: CGSize(width: 400, height: 400)) == nil)
        #expect(ImageMagnification(imageSize: CGSize(width: 100, height: 50), viewSize: .zero) == nil)
    }

    // MARK: Image rotation

    @Test func aQuarterTurnSwapsTheSidesAndKeepsThePixels() throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let image = NSImage(size: NSSize(width: 2, height: 1))
        image.addRepresentation(bitmap)

        let turned = try #require(image.rotated(byQuarterTurns: 1))
        #expect(turned.size == NSSize(width: 1, height: 2))
        let pixels = try #require(turned.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(pixels.width == 2)
        #expect(pixels.height == 4)

        let halfTurn = try #require(image.rotated(byQuarterTurns: 2))
        #expect(halfTurn.size == image.size)

        guard case .png = turned.encodedForSaving else {
            Issue.record("An edited image is saved as PNG")
            return
        }
    }

    // MARK: Windows

    @Test func anEditorOpenedFromTheStripHasTheMinimumContentAndNoFooter() {
        #expect(PreviewSize.editorWindowSize == CGSize(width: 390, height: 283))
    }

    @Test func editorsStepAwayFromTheCentre() {
        let centred = CGRect(x: 500, y: 400, width: 400, height: 300)
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(WindowCascade.origin(centeredFrame: centred, screenFrame: screenFrame, windowCount: 1) == CGPoint(x: 530, y: 370))
        #expect(WindowCascade.origin(centeredFrame: centred, screenFrame: screenFrame, windowCount: 3) == CGPoint(x: 590, y: 310))
    }

    @Test func editorsStayInsideTheRightAndBottomEdges() {
        let centred = CGRect(x: 500, y: 400, width: 400, height: 300)
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(WindowCascade.origin(centeredFrame: centred, screenFrame: screenFrame, windowCount: 30) == CGPoint(x: 1040, y: 0))
    }

    @Test func theColourPanelGoesToTheRightWhenItFits() {
        let origin = ColorPanelPlacement.origin(
            windowFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
            panelSize: CGSize(width: 230, height: 400),
            screenWidth: 1440
        )
        #expect(origin == CGPoint(x: 520, y: 50))
    }

    @Test func theColourPanelGoesToTheLeftOtherwise() {
        let origin = ColorPanelPlacement.origin(
            windowFrame: CGRect(x: 900, y: 100, width: 400, height: 300),
            panelSize: CGSize(width: 230, height: 400),
            screenWidth: 1440
        )
        #expect(origin == CGPoint(x: 650, y: 50))
    }
}
