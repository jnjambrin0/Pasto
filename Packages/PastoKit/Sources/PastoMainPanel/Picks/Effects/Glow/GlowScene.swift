/// What the suggestions glow shows: a faint ember by the suggestions button while suggestions
/// are offered, a burst while they are being worked out, and a calm band around the panel while
/// they are on show.
nonisolated enum GlowScene: Sendable {
    case closed
    case loading
    case open
}

/// The values of one scene that the glow eases towards, one spring each. Their meaning in the
/// shader is described in `GlowShaderSource`.
nonisolated struct GlowLevels: Equatable, Sendable {
    var bandAlpha: Float = 0
    var bandFlame: Float = 0
    var bandAmount: Float = 0
    var bandIntensity: Float = 0
    var noiseSpeed: Float = 0
    var fillAlpha: Float = 0
    var fillIntensity: Float = 0
    var fillDepth: Float = 0
    var focus: Float = 0
    var burstWeight: Float = 0
    var mouseWeight: Float = 0

    /// Every value, each driven by its own spring.
    static let springs: [any WritableKeyPath<GlowLevels, Float> & Sendable] = [
        \.bandAlpha, \.bandFlame, \.bandAmount, \.bandIntensity, \.noiseSpeed,
        \.fillAlpha, \.fillIntensity, \.fillDepth, \.focus, \.burstWeight, \.mouseWeight,
    ]
}

/// One scene of the glow's tuning.
nonisolated struct GlowSceneTuning: Equatable, Sendable {
    /// The values in a dark appearance.
    var levels: GlowLevels
    /// How quickly the springs arrive at this scene: their angular frequency.
    var arrival: Float
    // A light appearance replaces these four.
    var bandAlphaLight: Float
    var bandIntensityLight: Float
    var fillAlphaLight: Float
    var fillIntensityLight: Float

    /// What the springs chase in this scene, with the light variants in a light appearance.
    func targets(isDark: Bool) -> GlowLevels {
        guard !isDark else { return levels }
        var targets = levels
        targets.bandAlpha = bandAlphaLight
        targets.bandIntensity = bandIntensityLight
        targets.fillAlpha = fillAlphaLight
        targets.fillIntensity = fillIntensityLight
        return targets
    }
}
