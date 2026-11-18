import simd

/// A light that circles the panel's centre and tints the glow near it.
nonisolated struct GlowOrbit: Equatable, Sendable {
    /// Distance from the centre, in widths of the panel.
    var radius: Float
    /// How far the radius swings in and out.
    var breath: Float
    var degreesPerSecond: Float
    /// Starting angle, in degrees; also offsets the breathing.
    var phase: Float
}

/// Every number of the glow.
nonisolated struct GlowTuning: Sendable {
    var closed: GlowSceneTuning
    var loading: GlowSceneTuning
    var open: GlowSceneTuning

    // The swell of the fill while suggestions are being worked out.
    var waveFillAlpha: Float
    var waveFillDepth: Float
    var waveRise: Double
    var waveLife: Double
    var waveFall: Double
    /// Scales the overshoot of the rise.
    var waveSpring: Double

    // The burst that crosses the panel when suggestions are asked for.
    var burstSpeed: Float
    var burstDuration: Float
    var burstIntensity: Float

    /// Whether the pointer brightens the glow under it.
    var pointerBreath: Bool
    /// How long the glow takes to catch up with the pointer: the time constant of its lag.
    var pointerLag: Float

    // How the animated icon's excitement stirs the ember by the suggestions button.
    var emberReach: Float
    var emberSwell: Float
    var emberSpread: Float
    var emberFlare: Float

    /// The tones of the glow, repeated in turn over the lights; the same in both appearances.
    var hues: [SIMD3<Float>]
    var orbits: [GlowOrbit]

    func scene(_ scene: GlowScene) -> GlowSceneTuning {
        switch scene {
        case .closed: closed
        case .loading: loading
        case .open: open
        }
    }

    /// How many lights there are.
    static let lightCount = 11

    static let standard = GlowTuning(
        closed: GlowSceneTuning(
            levels: GlowLevels(
                bandAlpha: 0.17, bandFlame: 1, bandAmount: 1, bandIntensity: 1, noiseSpeed: 0,
                fillAlpha: 0.25, fillIntensity: 1, fillDepth: 1, focus: 1, burstWeight: 0, mouseWeight: 0
            ),
            arrival: 20,
            bandAlphaLight: 0.35, bandIntensityLight: 1, fillAlphaLight: 0.5, fillIntensityLight: 1
        ),
        loading: GlowSceneTuning(
            levels: GlowLevels(
                bandAlpha: 0.75, bandFlame: 1.5, bandAmount: 1, bandIntensity: 1.5, noiseSpeed: 6,
                fillAlpha: 0.25, fillIntensity: 1, fillDepth: 2, focus: 0, burstWeight: 1.5, mouseWeight: 0
            ),
            arrival: 10,
            bandAlphaLight: 1, bandIntensityLight: 1.5, fillAlphaLight: 0.5, fillIntensityLight: 1
        ),
        open: GlowSceneTuning(
            levels: GlowLevels(
                bandAlpha: 0.25, bandFlame: 1, bandAmount: 1, bandIntensity: 1.25, noiseSpeed: 2,
                fillAlpha: 0.25, fillIntensity: 1, fillDepth: 2, focus: 0, burstWeight: 0, mouseWeight: 0.799037
            ),
            arrival: 10,
            bandAlphaLight: 0.5, bandIntensityLight: 1.25, fillAlphaLight: 0.5, fillIntensityLight: 1
        ),
        waveFillAlpha: 0,
        waveFillDepth: 2,
        waveRise: 1,
        waveLife: 1,
        waveFall: 0.5,
        waveSpring: 1,
        burstSpeed: 6,
        burstDuration: 1,
        burstIntensity: 1,
        pointerBreath: true,
        pointerLag: 0.1,
        emberReach: 80,
        emberSwell: 0.25,
        emberSpread: 0.25,
        emberFlare: 0.4,
        hues: [
            SIMD3(1, 0.645833, 0.15),   // orange
            SIMD3(1, 0.833333, 0),      // amber
            SIMD3(0.95, 0.45125, 0.095), // dark orange
        ],
        // The phase is in degrees for the angle but goes into the breathing's sine as it is.
        orbits: [
            GlowOrbit(radius: 0.65, breath: 0.12, degreesPerSecond: 13, phase: -16),
            GlowOrbit(radius: 0.90, breath: 0.15, degreesPerSecond: -7, phase: 140),
            GlowOrbit(radius: 0.55, breath: 0.10, degreesPerSecond: 22, phase: 260),
            GlowOrbit(radius: 1.05, breath: 0.12, degreesPerSecond: -4, phase: 40),
            GlowOrbit(radius: 0.75, breath: 0.18, degreesPerSecond: 31, phase: 200),
            GlowOrbit(radius: 0.60, breath: 0.10, degreesPerSecond: -18, phase: 320),
            GlowOrbit(radius: 1.10, breath: 0.15, degreesPerSecond: 2, phase: 95),
            GlowOrbit(radius: 0.80, breath: 0.12, degreesPerSecond: -1, phase: 10),
            GlowOrbit(radius: 0.50, breath: 0.08, degreesPerSecond: -27, phase: 180),
            GlowOrbit(radius: 0.95, breath: 0.20, degreesPerSecond: 45, phase: 300),
            GlowOrbit(radius: 0.70, breath: 0.12, degreesPerSecond: -10, phase: 75),
        ]
    )
}
