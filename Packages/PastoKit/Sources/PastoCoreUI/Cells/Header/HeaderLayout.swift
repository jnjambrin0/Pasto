import Foundation
import PastoUI

/// The arrangement of a card's header for one density.
///
/// Offsets are measured from the header's trailing edge: positive ones stick out past it, where
/// the header clips.
nonisolated struct HeaderLayout: Sendable, Equatable {
    /// How a header that floats over full-size content keeps its text readable in the compact
    /// density, where there is no colour band.
    enum CompactStyle: Sendable, Equatable {
        /// Nothing behind the text, which takes the card's text colours.
        case transparent
        /// A dark shade behind white text, for images.
        case gradient
    }

    enum LabelAxis: Sendable, Equatable {
        /// Title above date.
        case vertical
        /// Date right after the title, on one line.
        case horizontal
    }

    // MARK: Values that move during a density transition

    /// Opacity of the colour band. The compact density has none.
    var bandAlpha: CGFloat
    var gradientAlpha: CGFloat
    var appIconAlpha: CGFloat
    var appIconSide: CGFloat
    /// Trailing edge of the application icon.
    var appIconOffset: CGFloat
    /// Trailing edge of the pinboard dot.
    var pinboardIconOffset: CGFloat

    // MARK: Values that jump

    /// Where the labels must end.
    var labelsTrailingOffset: CGFloat
    var labelAxis: LabelAxis
    var titleFont: CardFont
    var titleColor: CardTextColor
    var dateFont: CardFont
    var dateColor: CardTextColor
    var isDateCompact: Bool
    /// The labels sit on the colour band, which is what Increase Contrast may darken them over.
    var labelsOnBand: Bool

    /// - Parameters:
    ///   - isAppIconHidden: the item is on a pinboard, which shows its dot instead of the icon.
    ///   - hasSourceIcon: the item's source application has an icon.
    init(sizeClass: SizeClass, compactStyle: CompactStyle, isAppIconHidden: Bool, hasSourceIcon: Bool) {
        pinboardIconOffset = sizeClass == .compact ? -HeaderMetrics.sideInset : 8

        if sizeClass == .compact {
            let isGradient = compactStyle == .gradient
            bandAlpha = 0
            gradientAlpha = isGradient ? 1 : 0
            appIconAlpha = 0.9
            appIconSide = HeaderMetrics.appIconSide(for: sizeClass)
            appIconOffset = -8
            labelsTrailingOffset = isAppIconHidden && !hasSourceIcon ? -HeaderMetrics.sideInset : -30
            labelAxis = .horizontal
            titleFont = .headlineSemibold
            titleColor = isGradient ? .white(alpha: 0.85) : .primary
            dateFont = .body
            dateColor = isGradient ? .white(alpha: 0.55) : .secondary
            isDateCompact = true
            labelsOnBand = false
        } else {
            bandAlpha = 1
            gradientAlpha = 0
            appIconAlpha = isAppIconHidden ? 0 : 1
            appIconSide = HeaderMetrics.appIconSide(for: sizeClass)
            appIconOffset = HeaderMetrics.appIconOverhang
            // The labels stop where the visible part of the icon starts.
            labelsTrailingOffset = isAppIconHidden ? -HeaderMetrics.sideInset : HeaderMetrics.appIconOverhang - appIconSide
            labelAxis = .vertical
            titleFont = .title3Medium
            titleColor = .white(alpha: 1)
            dateFont = .callout
            dateColor = .white(alpha: 0.8)
            isDateCompact = false
            labelsOnBand = true
        }
    }

    // MARK: Increase Contrast

    /// Above this relative luminance a band counts as light: white on it is about 2:1 at most.
    static let lightBandLuminance = 0.45

    /// Whether the labels over a band of this sRGB colour are dark rather than white. Only with
    /// Increase Contrast on: otherwise they are always white.
    static func prefersDarkLabels(onBandRed red: Double, green: Double, blue: Double) -> Bool {
        relativeLuminance(red: red, green: green, blue: blue) > lightBandLuminance
    }

    /// The relative luminance of an sRGB colour as WCAG 2 defines it: 0 for black, 1 for white.
    static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The layout part-way through a density transition: opacities, the icon's size and
    /// the two icon offsets move linearly; everything else is the destination's from the start.
    static func blend(from source: HeaderLayout, to destination: HeaderLayout, progress: Double) -> HeaderLayout {
        var layout = destination
        layout.bandAlpha = .blend(from: source.bandAlpha, to: destination.bandAlpha, progress: progress)
        layout.gradientAlpha = .blend(from: source.gradientAlpha, to: destination.gradientAlpha, progress: progress)
        layout.appIconAlpha = .blend(from: source.appIconAlpha, to: destination.appIconAlpha, progress: progress)
        layout.appIconSide = .blend(from: source.appIconSide, to: destination.appIconSide, progress: progress)
        layout.appIconOffset = .blend(from: source.appIconOffset, to: destination.appIconOffset, progress: progress)
        layout.pinboardIconOffset = .blend(from: source.pinboardIconOffset, to: destination.pinboardIconOffset, progress: progress)
        return layout
    }
}
