import CoreGraphics

/// The numbers of the animated suggestions icon.
///
/// Distances are in *base units*: the radius of the icon's circle before it is scaled, which
/// is `side / (2 × canvasNormalisation)` points. "Resting" is the icon left alone; "excited",
/// the icon with the pointer right on it.
nonisolated enum PicksIconMetrics {
    // MARK: Instances

    /// In the toolbar's suggestions button, where it follows the pointer.
    static let toolbarSide: CGFloat = 20
    /// Above the permission request in the strip, where it never gets excited.
    static let placeholderSide: CGFloat = 28

    // MARK: Resting and excited

    /// Feeds the brightness of the sheen.
    static let restingLiveliness: Float = 1.4
    static let excitedLiveliness: Float = 1.6
    /// How many harmonics of the outline's motion show.
    static let restingModeCount: Float = 5
    static let excitedModeCount: Float = 10
    /// How much of the outline's motion shows.
    static let restingAmplitude: Float = 0.25
    static let excitedAmplitude: Float = 1.0
    /// Seconds per cycle of the outline's motion.
    static let restingCycle: Float = 3
    static let excitedCycle: Float = 2

    // MARK: Pointer and lean

    /// Beyond this distance, in base scales, the pointer no longer excites the icon.
    static let pointerReach: Float = 3.5
    /// Time constant of the mood, which follows the excitement.
    static let moodTimeConstant: Float = 0.3
    /// How far, in base units, the icon leans towards the pointer.
    static let maximumLean: Float = 0.4
    /// The lean's spring, in hertz, and its damping ratio.
    static let leanFrequency: Float = 3
    static let leanDamping: Float = 0.75
    /// The pointer distance, in base scales, at which the lean is full.
    static let leanSaturation: Float = 0.8

    // MARK: Size

    /// The icon grows by this fraction when excited…
    static let scalingGrowth: Float = 0.4
    static let scalingTimeConstant: Float = 0.01
    /// …and shrinks by this one while its button is pressed.
    static let pressShrink: Float = 0.06
    static let pressTimeConstant: Float = 0.02
    /// The scale of the outline at rest.
    static let baseScale: Float = 1.4

    // MARK: Canvas

    /// Converts the canvas reserve to multiples of the side.
    static let canvasNormalisation: Float = 1.317523
    static let canvasMargin: Float = 1.02

    // MARK: Drawing

    /// Points along the outline.
    static let outlineSegments = 96
    /// The fill turns around the icon, sweeping these warm tones; the first comes back at the end.
    static let fillColors: [CGColor] = [
        CGColor(srgbRed: 1.00, green: 0.58, blue: 0.16, alpha: 1),
        CGColor(srgbRed: 1.00, green: 0.80, blue: 0.22, alpha: 1),
        CGColor(srgbRed: 0.97, green: 0.42, blue: 0.26, alpha: 1),
        CGColor(srgbRed: 1.00, green: 0.70, blue: 0.30, alpha: 1),
        CGColor(srgbRed: 1.00, green: 0.58, blue: 0.16, alpha: 1),
    ]
    /// A soft highlight up and to the left of the centre, so the shape reads as round.
    static let sheenCenter = CGPoint(x: -0.3, y: 0.35)
    /// Radius of the highlight, in radii of the icon's circle.
    static let sheenRadius: CGFloat = 1.1
    /// The highlight's opacity per unit of liveliness above 1.
    static let sheenPerLiveliness: Float = 1.2
}
