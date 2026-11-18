import CoreGraphics
import PastoUI
import Testing
@testable import PastoCoreUI

/// The geometry, fonts and colours of a card's header in every density.
@Suite struct HeaderLayoutTests {
    func layout(
        _ sizeClass: SizeClass,
        style: HeaderLayout.CompactStyle = .transparent,
        iconHidden: Bool = false,
        hasSourceIcon: Bool = true
    ) -> HeaderLayout {
        HeaderLayout(sizeClass: sizeClass, compactStyle: style, isAppIconHidden: iconHidden, hasSourceIcon: hasSourceIcon)
    }

    @Test func densitiesWithABand() {
        let expected: [(SizeClass, icon: CGFloat, labelsTrailing: CGFloat)] = [(.large, 84, -70), (.regular, 80, -66), (.small, 76, -62)]
        for (sizeClass, icon, labelsTrailing) in expected {
            let layout = layout(sizeClass)
            #expect(layout.appIconSide == icon)
            #expect(layout.appIconOffset == 14)
            #expect(layout.labelsTrailingOffset == labelsTrailing)
            #expect(layout.pinboardIconOffset == 8)
            #expect(layout.bandAlpha == 1)
            #expect(layout.gradientAlpha == 0)
            #expect(layout.appIconAlpha == 1)
            #expect(layout.labelAxis == .vertical)
            #expect(layout.titleFont == .title3Medium)
            #expect(layout.titleColor == .white(alpha: 1))
            #expect(layout.dateFont == .callout)
            #expect(layout.dateColor == .white(alpha: 0.8))
            #expect(!layout.isDateCompact)
        }
    }

    @Test func labelSpacing() {
        #expect(HeaderMetrics.stackedLabelSpacing == -1)
        #expect(HeaderMetrics.inlineLabelSpacing == 0)
        #expect(HeaderMetrics.sideInset == 12)
        #expect(HeaderMetrics.gradientHeight == 64)
    }

    @Test func pinnedItemsHaveNoIconAndWiderLabels() {
        for sizeClass in [SizeClass.large, .regular, .small] {
            let layout = layout(sizeClass, iconHidden: true)
            #expect(layout.appIconAlpha == 0)
            #expect(layout.labelsTrailingOffset == -12)
        }
    }

    @Test func compact() {
        let layout = layout(.compact)
        #expect(layout.appIconSide == 20)
        #expect(layout.appIconOffset == -8)
        #expect(layout.appIconAlpha == 0.9)
        #expect(layout.pinboardIconOffset == -12)
        #expect(layout.labelsTrailingOffset == -30)
        #expect(layout.bandAlpha == 0)
        #expect(layout.gradientAlpha == 0)
        #expect(layout.labelAxis == .horizontal)
        #expect(layout.titleFont == .headlineSemibold)
        #expect(layout.dateFont == .body)
        #expect(layout.isDateCompact)
        #expect(layout.titleColor == .primary)
        #expect(layout.dateColor == .secondary)
    }

    @Test func compactOverAnImage() {
        let layout = layout(.compact, style: .gradient)
        #expect(layout.gradientAlpha == 1)
        #expect(layout.bandAlpha == 0)
        #expect(layout.titleColor == .white(alpha: 0.85))
        #expect(layout.dateColor == .white(alpha: 0.55))
    }

    @Test func compactLabelsOnlyWidenWithoutAnyIcon() {
        #expect(layout(.compact, iconHidden: true, hasSourceIcon: true).labelsTrailingOffset == -30)
        #expect(layout(.compact, iconHidden: true, hasSourceIcon: false).labelsTrailingOffset == -12)
        #expect(layout(.compact, iconHidden: false, hasSourceIcon: false).labelsTrailingOffset == -30)
    }

    @Test func compactStyleDoesNotMatterWithABand() {
        #expect(layout(.small, style: .gradient) == layout(.small, style: .transparent))
    }

    @Test func transitionMovesSizesAndOpacitiesLinearly() {
        let small = layout(.small, style: .gradient)
        let compact = layout(.compact, style: .gradient)
        let halfway = HeaderLayout.blend(from: small, to: compact, progress: 0.5)

        #expect(halfway.bandAlpha == 0.5)
        #expect(halfway.gradientAlpha == 0.5)
        #expect(abs(halfway.appIconAlpha - 0.95) < 1e-9)
        #expect(halfway.appIconSide == 48)
        #expect(halfway.appIconOffset == 3)
        #expect(halfway.pinboardIconOffset == -2)
    }

    @Test func transitionSwitchesEverythingElseAtOnce() {
        let small = layout(.small)
        let compact = layout(.compact)
        let start = HeaderLayout.blend(from: small, to: compact, progress: 0)

        // The numbers are still the source's…
        #expect(start.appIconSide == small.appIconSide)
        #expect(start.bandAlpha == small.bandAlpha)
        // …but fonts, colours, the date's format and the label arrangement are the destination's.
        #expect(start.titleFont == compact.titleFont)
        #expect(start.titleColor == compact.titleColor)
        #expect(start.dateFont == compact.dateFont)
        #expect(start.dateColor == compact.dateColor)
        #expect(start.isDateCompact)
        #expect(start.labelAxis == .horizontal)
        #expect(start.labelsTrailingOffset == compact.labelsTrailingOffset)
    }

    @Test func transitionEndsAtTheDestination() {
        for (source, destination) in [(SizeClass.small, SizeClass.compact), (.compact, .small), (.regular, .large)] {
            #expect(HeaderLayout.blend(from: layout(source), to: layout(destination), progress: 1) == layout(destination))
        }
    }

    // MARK: Increase Contrast

    @Test func onlyBandedDensitiesPutTheLabelsOnTheBand() {
        #expect(layout(.small).labelsOnBand)
        #expect(layout(.large).labelsOnBand)
        #expect(!layout(.compact).labelsOnBand)
        #expect(!layout(.compact, style: .gradient).labelsOnBand)
        #expect(!HeaderLayout.blend(from: layout(.small), to: layout(.compact), progress: 0).labelsOnBand)
    }

    @Test func relativeLuminanceFollowsWCAG() {
        #expect(HeaderLayout.relativeLuminance(red: 0, green: 0, blue: 0) == 0)
        #expect(abs(HeaderLayout.relativeLuminance(red: 1, green: 1, blue: 1) - 1) < 1e-9)
        // sRGB #808080.
        #expect(abs(HeaderLayout.relativeLuminance(red: 128 / 255, green: 128 / 255, blue: 128 / 255) - 0.2158) < 1e-4)
        // Green weighs most, blue least.
        #expect(abs(HeaderLayout.relativeLuminance(red: 0, green: 1, blue: 0) - 0.7152) < 1e-9)
        #expect(abs(HeaderLayout.relativeLuminance(red: 0, green: 0, blue: 1) - 0.0722) < 1e-9)
    }

    @Test func lightBandsGetDarkLabels() {
        // The pinboards' yellow, #F2B600.
        #expect(HeaderLayout.prefersDarkLabels(onBandRed: 242 / 255, green: 182 / 255, blue: 0))
        #expect(HeaderLayout.prefersDarkLabels(onBandRed: 0.9, green: 0.9, blue: 0.9))
        // The default gray band, #8E8E93, and a saturated blue keep white labels.
        #expect(!HeaderLayout.prefersDarkLabels(onBandRed: 142 / 255, green: 142 / 255, blue: 147 / 255))
        #expect(!HeaderLayout.prefersDarkLabels(onBandRed: 0, green: 122 / 255, blue: 1))
    }
}
