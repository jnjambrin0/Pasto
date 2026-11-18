import AppKit

/// Layout and timing values for the suggestions mode of the panel. The glow and the animated icon
/// keep theirs in `GlowTuning` and `PicksIconMetrics`.
nonisolated enum PicksPanelMetrics {
    // MARK: Hand-over

    /// Suggestions never appear sooner than this after the button is clicked, however quickly
    /// they are ready.
    static let minimumHandoverWait: Duration = .seconds(1.2804)

    // MARK: Toolbar button

    static let buttonAnimationDuration: CFTimeInterval = 0.32
    /// The button's scale, entering the mode: it swells and shrinks away.
    static let buttonScalesWhenActivating: [CGFloat] = [1, 1.22, 0.2]
    /// The button's scale, leaving the mode: it grows back with a slight overshoot.
    static let buttonScalesWhenDeactivating: [CGFloat] = [0.2, 1.12, 1]
    static let buttonKeyTimes: [NSNumber] = [0, 0.45, 1]

    // MARK: Wave

    /// How long the wave takes to reach the farthest card, as a delay per unit of distance
    /// (distances go from 0 at the origin to 1 at the farthest card).
    static let waveDelay: CFTimeInterval = 0.4074
    static let waveFadeDuration: CFTimeInterval = 0.2716
    static let waveRippleDuration: CFTimeInterval = 0.5432
    /// Hiding runs at this fraction of the times above; revealing at full length.
    static let waveHideTimeScale: CFTimeInterval = 0.75
    /// How much weaker the ripple is at the farthest card than at the origin.
    static let waveStrengthFalloff: CGFloat = 0.55
    /// The perspective is 1 / (this × the card's height).
    static let wavePerspectiveDepth: CGFloat = 5
    /// First keyframe: the card rises by this fraction of its height, tilts back and grows.
    static let waveRise: CGFloat = 0.03
    static let waveTilt: CGFloat = 0.16
    static let waveSwell: CGFloat = 0.02
    /// Second keyframe: it dips by this fraction of its height and tilts forward.
    static let waveDip: CGFloat = 0.01
    static let waveCounterTilt: CGFloat = 0.06
    static let waveKeyTimes: [NSNumber] = [0, 0.28, 0.62, 1]

    // MARK: Placeholder

    // The line of text and the centre of the access block are those of every text the strip
    // shows without cards: `MainPanelMetrics.emptyText…`.

    static let accessTitleFontSize: CGFloat = 15
    static let accessSubtitleFontSize: CGFloat = 13
    static let accessSubtitleMaximumWidth: CGFloat = 460
    /// Between the elements of the access block…
    static let accessSpacing: CGFloat = 6
    /// …except after the icon and after the subtitle.
    static let accessSpacingAfterIcon: CGFloat = 10
    static let accessSpacingAfterSubtitle: CGFloat = 10
    /// Between the two buttons.
    static let accessButtonSpacing: CGFloat = 10
}
