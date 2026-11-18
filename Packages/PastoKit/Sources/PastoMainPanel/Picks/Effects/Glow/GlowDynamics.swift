import CoreGraphics
import Foundation
import simd

/// What the glow's shader receives every frame, in the order its structure declares them: 26
/// floats with no padding.
nonisolated struct GlowUniforms: Equatable, Sendable {
    /// The view's size, in points.
    var sizeX: Float
    var sizeY: Float
    /// Pixels per point.
    var scale: Float
    var cornerRadius: Float
    /// Where the reveal starts, in the width-normalised coordinates of `GlowState.pointerTarget`.
    var originX: Float
    var originY: Float
    /// Seconds since the burst started, at most `GlowState.maximumBurstTime`.
    var burstTime: Float
    var burstWeight: Float
    var noiseX: Float
    var noiseY: Float
    var noiseZ: Float
    var bandAlpha: Float
    var bandFlame: Float
    var bandAmount: Float
    var bandIntensity: Float
    var fillAlpha: Float
    var fillIntensity: Float
    var fillDepth: Float
    var focus: Float
    var mouseX: Float
    var mouseY: Float
    var mouseWeight: Float
    var emberReach: Float
    var burstSpeed: Float
    var burstDuration: Float
    var burstIntensity: Float
}

/// Everything the glow remembers between frames, and how one frame moves it on. Pure: the view
/// feeds it the clock, the appearance, the pointer and the excitement, and draws the uniforms it
/// returns.
nonisolated struct GlowState: Sendable {
    /// Where a pointer outside the view is taken to be: far enough to light nothing.
    static let farPointer = SIMD2<Float>(9, 9)
    /// `burstTime` stops growing here, and stands at it while there is no burst.
    static let maximumBurstTime: Float = 10
    /// A scene with a burst weight under this has no burst.
    static let burstThreshold: Float = 0.001
    /// The springs never get slower than this, whatever a scene's arrival says.
    static let minimumArrival: Float = 0.5
    /// Damping of the springs, in multiples of their arrival.
    static let springDamping: Float = 1.7

    // How fast the noise drifts and the colours turn, per unit of noise speed per second.
    static let noiseDrift = SIMD3<Float>(0.007, -0.011, 0.06)
    static let colourBaseRate: Float = 0.3
    static let colourNoiseRate: Float = 0.7
    /// How fast the breathing of the lights goes round, per unit of colour time.
    static let breathRate: Float = 0.17

    private(set) var sceneShown = GlowScene.closed
    /// When the current burst started; nil when there is none, or motion is reduced.
    private(set) var burstStart: CFTimeInterval?
    /// When the scene left the burst, letting its swell fall.
    private(set) var waveReleased: CFTimeInterval?
    private(set) var levels: GlowLevels
    private(set) var velocities = GlowLevels()
    private(set) var pointer = GlowState.farPointer
    private(set) var noiseOffset = SIMD3<Float>(repeating: 0)
    private(set) var colourTime: Float = 0
    private(set) var lights = [SIMD2<Float>](repeating: .zero, count: GlowTuning.lightCount)

    /// Starts at rest in the closed scene.
    init(tuning: GlowTuning) {
        levels = tuning.closed.targets(isDark: true)
    }

    // MARK: - Steps of a frame

    /// Takes in a change of scene: entering one with a burst starts it (unless motion is
    /// reduced); leaving it lets the swell fall.
    mutating func show(_ scene: GlowScene, at now: CFTimeInterval, motion: Float, tuning: GlowTuning) {
        guard scene != sceneShown else { return }
        let newWeight = tuning.scene(scene).levels.burstWeight
        let shownWeight = tuning.scene(sceneShown).levels.burstWeight
        if newWeight > Self.burstThreshold, shownWeight < Self.burstThreshold {
            burstStart = motion > 0 ? now : nil
            waveReleased = nil
        } else if newWeight < Self.burstThreshold, waveReleased == nil {
            waveReleased = now
        }
        sceneShown = scene
    }

    /// Moves every value towards its target with a damped spring:
    /// `a = w²·(target − value) − 1.7·w·velocity`, then velocity and value, in that order.
    mutating func stepSprings(toward targets: GlowLevels, arrival: Float, dt: Float) {
        let w = max(arrival, Self.minimumArrival)
        for keyPath in GlowLevels.springs {
            let acceleration = w * w * (targets[keyPath: keyPath] - levels[keyPath: keyPath])
                - Self.springDamping * w * velocities[keyPath: keyPath]
            velocities[keyPath: keyPath] += dt * acceleration
            levels[keyPath: keyPath] += dt * velocities[keyPath: keyPath]
        }
    }

    /// Drifts the noise and turns the colours, at the speed of the current noise speed. With
    /// motion reduced the noise stands still and the colours turn at their base rate.
    mutating func advanceNoise(dt: Float, motion: Float) {
        let speed = motion * levels.noiseSpeed
        noiseOffset += Self.noiseDrift * (dt * speed)
        colourTime += dt * (Self.colourBaseRate + Self.colourNoiseRate * speed)
    }

    /// Places every light on its orbit at the current colour time.
    mutating func placeLights(on orbits: [GlowOrbit]) {
        lights = orbits.map { orbit in
            let angle = (orbit.degreesPerSecond * colourTime + orbit.phase) * .pi / 180
            let radius = orbit.radius + orbit.breath * sin(orbit.phase + Self.breathRate * colourTime)
            return SIMD2(cos(angle), sin(angle)) * radius
        }
    }

    /// Follows the pointer with a lag of time constant `lag`.
    mutating func followPointer(to target: SIMD2<Float>, dt: Float, lag: Float) {
        guard dt > 0 else { return }
        pointer += (target - pointer) * (1 - exp(-dt / max(lag, 0.001)))
    }

    // MARK: - Reading

    /// Where the pointer is, in coordinates normalised by the view's width and centred on it
    /// (the y axis scaled by height ÷ width); `farPointer` outside the view or without one.
    /// `location` is in the view's own coordinates.
    static func pointerTarget(location: CGPoint?, size: CGSize) -> SIMD2<Float> {
        guard let location, size.width > 0, size.height > 0,
              CGRect(origin: .zero, size: size).contains(location)
        else { return farPointer }
        return normalised(location, in: size)
    }

    /// A point of the view in the coordinates the shader works in.
    static func normalised(_ point: CGPoint, in size: CGSize) -> SIMD2<Float> {
        SIMD2(
            Float(point.x / size.width - 0.5),
            Float((point.y / size.height - 0.5) * (size.height / size.width))
        )
    }

    /// The swell of the fill: rises when a burst starts, with back easing whose overshoot the
    /// falling curve (1 until the release) cuts off, holds, and falls once released or once it
    /// has lived its life.
    func wave(at now: CFTimeInterval, tuning: GlowTuning) -> Float {
        guard let burstStart else { return 0 }
        let rise = max(tuning.waveRise, 0.01)
        let fall = max(tuning.waveFall, 0.01)
        let release = min(burstStart + rise + tuning.waveLife, waveReleased ?? .infinity)
        let p = min(max((now - burstStart) / rise, 0), 1) - 1
        let overshoot = 1.70158 * tuning.waveSpring
        let rising = 1 + (overshoot + 1) * p * p * p + overshoot * p * p
        let q = min(max((now - release) / fall, 0), 1)
        let falling = 1 - q * q * (3 - 2 * q)
        return Float(min(rising, falling))
    }

    /// The tones for the lights: the palette repeated in turn, with an opaque fourth component
    /// so that each one takes the 16 bytes of a shader `float4`.
    static func lightHues(_ hues: [SIMD3<Float>]) -> [SIMD4<Float>] {
        guard !hues.isEmpty else { return [] }
        return (0..<GlowTuning.lightCount).map { SIMD4(hues[$0 % hues.count], 1) }
    }

    /// The uniforms of a frame drawn at `now`.
    /// - Parameters:
    ///   - origin: Where the reveal starts, in the view's coordinates.
    ///   - excitement: The animated icon's, 0…1.
    func uniforms(
        at now: CFTimeInterval,
        size: CGSize,
        scale: CGFloat,
        cornerRadius: CGFloat,
        origin: CGPoint,
        excitement: Float,
        tuning: GlowTuning
    ) -> GlowUniforms {
        let normalisedOrigin = Self.normalised(origin, in: size)
        let wave = wave(at: now, tuning: tuning)
        // The icon stirs the glow only where the scene keeps it focused on the button.
        let stir = excitement * levels.focus
        let burstTime = burstStart.map { min(Float(now - $0), Self.maximumBurstTime) } ?? Self.maximumBurstTime
        return GlowUniforms(
            sizeX: Float(size.width),
            sizeY: Float(size.height),
            scale: Float(scale),
            cornerRadius: Float(cornerRadius),
            originX: normalisedOrigin.x,
            originY: normalisedOrigin.y,
            burstTime: burstTime,
            burstWeight: levels.burstWeight,
            noiseX: noiseOffset.x,
            noiseY: noiseOffset.y,
            noiseZ: noiseOffset.z,
            bandAlpha: levels.bandAlpha,
            bandFlame: levels.bandFlame,
            bandAmount: levels.bandAmount * (1 + stir * tuning.emberSpread),
            bandIntensity: levels.bandIntensity * (1 + stir * tuning.emberFlare),
            fillAlpha: levels.fillAlpha + wave * tuning.waveFillAlpha,
            fillIntensity: levels.fillIntensity,
            fillDepth: max(levels.fillDepth, wave * tuning.waveFillDepth),
            focus: levels.focus,
            mouseX: pointer.x,
            mouseY: pointer.y,
            mouseWeight: tuning.pointerBreath ? levels.mouseWeight : 0,
            emberReach: tuning.emberReach * (1 + stir * tuning.emberSwell),
            burstSpeed: tuning.burstSpeed,
            burstDuration: tuning.burstDuration,
            burstIntensity: tuning.burstIntensity
        )
    }
}
