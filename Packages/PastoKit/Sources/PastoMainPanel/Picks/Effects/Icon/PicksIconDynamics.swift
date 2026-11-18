import CoreGraphics
import Foundation
import simd

/// What one frame of the icon draws with.
nonisolated struct PicksIconUniforms: Equatable, Sendable {
    /// Half the view's side, in base units.
    var unit: Float
    var liveliness: Float
    var modeCount: Float
    /// The lean, in the view's normalised coordinates (half a side = 1).
    var shiftX: Float
    var shiftY: Float
    var scale: Float
    var aspectX: Float
    var aspectY: Float
}

/// Everything the icon remembers between frames.
nonisolated struct PicksIconState: Equatable, Sendable {
    /// How close the pointer is, 0…1; recomputed every frame, not smoothed.
    var excitement: Float = 0
    /// The excitement, slowly: drives the pace and liveliness of the motion.
    var mood: Float = 0
    /// The excitement, quickly: drives the growth.
    var scaling: Float = 0
    /// 1 while the button is held down, smoothed.
    var press: Float = 0
    /// Where in its loop the outline is, 0..<1.
    var phase: Float = 0
    /// How far the icon leans towards the pointer, in normalised coordinates.
    var lean = SIMD2<Float>.zero
    var leanVelocity = SIMD2<Float>.zero

    /// One frame.
    /// - Parameters:
    ///   - pointer: Where the pointer is, in the view's coordinates; nil when the icon does not
    ///     follow it or cannot tell.
    ///   - unit: Half the view's side, in base units.
    mutating func advance(pointer: CGPoint?, size: CGSize, isPressed: Bool, unit: Float, dt: Float, motion: Float) {
        let vector = pointer.flatMap { PicksIconDynamics.pointerVector(location: $0, size: size, lean: lean) }
        excitement = PicksIconDynamics.excitement(pointerVector: vector, unit: unit, motion: motion)

        mood = PicksIconDynamics.follow(mood, toward: excitement, dt: dt, timeConstant: PicksIconMetrics.moodTimeConstant)
        scaling = PicksIconDynamics.follow(scaling, toward: excitement, dt: dt, timeConstant: PicksIconMetrics.scalingTimeConstant)
        press = PicksIconDynamics.follow(press, toward: isPressed ? 1 : 0, dt: dt, timeConstant: PicksIconMetrics.pressTimeConstant)

        let target = PicksIconDynamics.leanTarget(pointerVector: vector, excitement: excitement, unit: unit)
        (lean, leanVelocity) = PicksIconDynamics.stepLean(lean, velocity: leanVelocity, toward: target, dt: dt)

        phase = PicksIconDynamics.advancedPhase(phase, mood: mood, dt: dt, motion: motion)
    }
}

/// The icon's motion, as pure functions.
nonisolated enum PicksIconDynamics {
    /// How many sides of the icon its view is: room for the outline at its largest, grown and
    /// breathing, plus the lean and its overshoot when it follows the pointer.
    static func canvasFactor(reach: PicksIconOutline.Reach, respondsToPointer: Bool) -> Float {
        let m = PicksIconMetrics.self
        let amplitude = respondsToPointer ? m.excitedAmplitude : m.restingAmplitude
        let extent = reach.resting + amplitude * reach.breathing
        let reserve: Float
        if respondsToPointer {
            let damping = m.leanDamping
            let overshoot = exp(-Float.pi * damping / (1 - damping * damping).squareRoot())
            reserve = m.baseScale * (1 + m.scalingGrowth) * extent + m.maximumLean * (1 + overshoot)
        } else {
            reserve = m.baseScale * extent
        }
        return reserve / m.canvasNormalisation * m.canvasMargin
    }

    /// Half the view's side in base units, for a canvas factor.
    static func unit(canvasFactor: Float) -> Float {
        canvasFactor * PicksIconMetrics.canvasNormalisation
    }

    /// The pointer relative to the leaning icon, in normalised coordinates: ±1 at the view's
    /// edges along its shorter side. Nil for a view with no size.
    static func pointerVector(location: CGPoint, size: CGSize, lean: SIMD2<Float>) -> SIMD2<Float>? {
        guard size.width > 0, size.height > 0 else { return nil }
        let position = SIMD2(Float(location.x / size.width), Float(location.y / size.height))
        return (2 * position - 1) * aspect(of: size) - lean
    }

    static func aspect(of size: CGSize) -> SIMD2<Float> {
        guard size.width > 0, size.height > 0 else { return SIMD2(1, 1) }
        return SIMD2(Float(max(1, size.width / size.height)), Float(max(1, size.height / size.width)))
    }

    /// 1 with the pointer on the icon, falling to 0 at `pointerReach` base scales; always 0 with
    /// motion reduced or no pointer.
    static func excitement(pointerVector: SIMD2<Float>?, unit: Float, motion: Float) -> Float {
        guard let pointerVector else { return 0 }
        let reach = PicksIconMetrics.pointerReach * PicksIconMetrics.baseScale
        let closeness = 1 - unit * length(pointerVector) / reach
        return motion * min(max(closeness, 0), 1)
    }

    /// Where the lean is headed: towards the pointer, more the closer and more excited.
    static func leanTarget(pointerVector: SIMD2<Float>?, excitement: Float, unit: Float) -> SIMD2<Float> {
        guard let pointerVector, excitement > 0, unit > 0 else { return .zero }
        let distance = length(pointerVector)
        guard distance > 0 else { return .zero }
        let m = PicksIconMetrics.self
        let reach = min(1, unit * distance / (m.baseScale * m.leanSaturation))
        return pointerVector / distance * (m.maximumLean * reach * excitement / unit)
    }

    /// Exponential smoothing with time constant `timeConstant`.
    static func follow(_ value: Float, toward target: Float, dt: Float, timeConstant: Float) -> Float {
        value + (target - value) * (1 - exp(-dt / timeConstant))
    }

    /// One step of the lean's damped spring.
    static func stepLean(
        _ position: SIMD2<Float>, velocity: SIMD2<Float>, toward target: SIMD2<Float>, dt: Float
    ) -> (position: SIMD2<Float>, velocity: SIMD2<Float>) {
        let omega = 2 * Float.pi * PicksIconMetrics.leanFrequency
        let damping = 2 * PicksIconMetrics.leanDamping * omega
        let velocity = velocity + dt * (omega * omega * (target - position) - damping * velocity)
        return (position + dt * velocity, velocity)
    }

    /// The loop goes round once every `restingCycle` seconds at rest and every `excitedCycle`
    /// when excited; it stands still with motion reduced.
    static func advancedPhase(_ phase: Float, mood: Float, dt: Float, motion: Float) -> Float {
        let m = PicksIconMetrics.self
        let rate = (1 - mood) / m.restingCycle + mood / m.excitedCycle
        let advanced = phase + dt * motion * rate
        return advanced - advanced.rounded(.down)
    }

    /// The frame's uniforms. `modes` is how many harmonics the outline's motion has.
    static func uniforms(state: PicksIconState, unit: Float, modes: Int, size: CGSize) -> PicksIconUniforms {
        let m = PicksIconMetrics.self
        let mood = state.mood
        let aspect = aspect(of: size)
        return PicksIconUniforms(
            unit: unit,
            liveliness: m.restingLiveliness * (1 - mood) + m.excitedLiveliness * mood,
            modeCount: min(m.restingModeCount * (1 - mood) + m.excitedModeCount * mood, Float(modes)),
            shiftX: state.lean.x,
            shiftY: state.lean.y,
            scale: m.baseScale * (1 + m.scalingGrowth * state.scaling) * (1 - m.pressShrink * state.press),
            aspectX: aspect.x,
            aspectY: aspect.y
        )
    }

    /// How much of the outline's motion shows at a mood.
    static func amplitude(mood: Float) -> Float {
        PicksIconMetrics.restingAmplitude * (1 - mood) + PicksIconMetrics.excitedAmplitude * mood
    }
}
