import CoreGraphics
import Foundation
import simd
import Testing
@testable import PastoMainPanel

@Suite struct PicksIconDynamicsTests {
    // MARK: - Canvas

    @Test func canvasMakesRoomForGrowthAndLeanWhenFollowingThePointer() {
        let factor = PicksIconDynamics.canvasFactor(reach: .init(resting: 1, breathing: 0), respondsToPointer: true)
        // (1.4 × 1.4 + 0.4 × (1 + e^(−π·0.75/√(1 − 0.75²)))) / 1.317523 × 1.02
        #expect(abs(factor - 1.835847) < 1e-5)
    }

    @Test func canvasOfAQuietIconOnlyHoldsItsBreathing() {
        let still = PicksIconDynamics.canvasFactor(reach: .init(resting: 1, breathing: 0), respondsToPointer: false)
        #expect(abs(still - 1.083853) < 1e-5)
        let breathing = PicksIconDynamics.canvasFactor(reach: .init(resting: 1, breathing: 0.2), respondsToPointer: false)
        #expect(abs(breathing - 1.138046) < 1e-5)   // a quarter of the breathing
    }

    @Test func unitIsHalfTheViewInBaseUnits() {
        #expect(abs(PicksIconDynamics.unit(canvasFactor: 2) - 2.635046) < 1e-5)
    }

    // MARK: - Pointer

    @Test func pointerVectorIsRelativeToTheLeaningCentre() {
        let size = CGSize(width: 40, height: 40)
        #expect(PicksIconDynamics.pointerVector(location: CGPoint(x: 30, y: 20), size: size, lean: .zero) == SIMD2(0.5, 0))
        let leaning = PicksIconDynamics.pointerVector(location: CGPoint(x: 30, y: 20), size: size, lean: SIMD2(0.1, 0.2))
        #expect(abs(leaning!.x - 0.4) < 1e-6 && abs(leaning!.y + 0.2) < 1e-6)
        #expect(PicksIconDynamics.pointerVector(location: CGPoint(x: 60, y: 20), size: CGSize(width: 80, height: 40), lean: .zero) == SIMD2(1, 0))
        #expect(PicksIconDynamics.pointerVector(location: .zero, size: .zero, lean: .zero) == nil)
    }

    @Test func excitementFallsWithDistance() {
        let near = PicksIconDynamics.excitement(pointerVector: SIMD2(0.5, 0), unit: 3, motion: 1)
        #expect(abs(near - (1 - 1.5 / 4.9)) < 1e-6)
        #expect(PicksIconDynamics.excitement(pointerVector: .zero, unit: 3, motion: 1) == 1)
        #expect(PicksIconDynamics.excitement(pointerVector: SIMD2(2, 0), unit: 3, motion: 1) == 0)
        #expect(PicksIconDynamics.excitement(pointerVector: SIMD2(0.5, 0), unit: 3, motion: 0) == 0)
        #expect(PicksIconDynamics.excitement(pointerVector: nil, unit: 3, motion: 1) == 0)
    }

    // MARK: - Lean

    @Test func leanHeadsTowardsThePointer() {
        let target = PicksIconDynamics.leanTarget(pointerVector: SIMD2(0.3, 0.4), excitement: 0.5, unit: 2)
        // 0.4 × min(1, 2 × 0.5 / (1.4 × 0.8)) × 0.5 / 2, along (0.6, 0.8).
        let magnitude: Float = 0.4 * (1 / 1.12) * 0.5 / 2
        #expect(abs(target.x - 0.6 * magnitude) < 1e-6)
        #expect(abs(target.y - 0.8 * magnitude) < 1e-6)
    }

    @Test func noLeanWithoutExcitementOrDirection() {
        #expect(PicksIconDynamics.leanTarget(pointerVector: SIMD2(0.3, 0.4), excitement: 0, unit: 2) == .zero)
        #expect(PicksIconDynamics.leanTarget(pointerVector: .zero, excitement: 1, unit: 2) == .zero)
        #expect(PicksIconDynamics.leanTarget(pointerVector: nil, excitement: 1, unit: 2) == .zero)
    }

    @Test func leanSpringStep() {
        let (position, velocity) = PicksIconDynamics.stepLean(.zero, velocity: .zero, toward: SIMD2(1, 0), dt: 0.01)
        let omegaSquared = (6 * Float.pi) * (6 * Float.pi)
        #expect(abs(velocity.x - 0.01 * omegaSquared) < 1e-4)
        #expect(abs(position.x - 0.0001 * omegaSquared) < 1e-5)
        #expect(velocity.y == 0)
    }

    @Test func leanSettlesWithASmallOvershoot() {
        var position = SIMD2<Float>.zero
        var velocity = SIMD2<Float>.zero
        var peak: Float = 0
        for _ in 0..<240 {
            (position, velocity) = PicksIconDynamics.stepLean(position, velocity: velocity, toward: SIMD2(1, 0), dt: 1.0 / 120)
            peak = max(peak, position.x)
        }
        #expect(abs(position.x - 1) < 1e-3)
        #expect(peak > 1 && peak < 1.05)   // ζ = 0.75 overshoots by about 3 %
    }

    // MARK: - Smoothing and phase

    @Test func exponentialFollowing() {
        let value = PicksIconDynamics.follow(0, toward: 1, dt: 0.3, timeConstant: 0.3)
        #expect(abs(value - (1 - exp(-1))) < 1e-6)
    }

    @Test func phaseWrapsAndQuickensWithTheMood() {
        #expect(abs(PicksIconDynamics.advancedPhase(0.9, mood: 0, dt: 0.6, motion: 1) - 0.1) < 1e-5)
        #expect(abs(PicksIconDynamics.advancedPhase(0, mood: 1, dt: 0.5, motion: 1) - 0.25) < 1e-6)
        #expect(PicksIconDynamics.advancedPhase(0.4, mood: 1, dt: 0.5, motion: 0) == 0.4)
    }

    // MARK: - Uniforms

    @Test func restingUniforms() {
        let uniforms = PicksIconDynamics.uniforms(state: PicksIconState(), unit: 3, modes: 10, size: CGSize(width: 40, height: 40))
        #expect(uniforms.liveliness == 1.4)
        #expect(uniforms.modeCount == 5)
        #expect(uniforms.scale == 1.4)
        #expect(uniforms.aspectX == 1 && uniforms.aspectY == 1)
        #expect(PicksIconDynamics.amplitude(mood: 0) == 0.25)
    }

    @Test func excitedAndPressedUniforms() {
        let state = PicksIconState(excitement: 1, mood: 1, scaling: 1, press: 1, phase: 0, lean: SIMD2(0.1, -0.2))
        let uniforms = PicksIconDynamics.uniforms(state: state, unit: 3, modes: 8, size: CGSize(width: 40, height: 20))
        #expect(abs(uniforms.liveliness - 1.6) < 1e-6)
        #expect(uniforms.modeCount == 8)   // limited by the harmonics there are
        #expect(abs(uniforms.scale - 1.4 * 1.4 * 0.94) < 1e-5)
        #expect(uniforms.shiftX == 0.1 && uniforms.shiftY == -0.2)
        #expect(uniforms.aspectX == 2 && uniforms.aspectY == 1)
        #expect(PicksIconDynamics.amplitude(mood: 1) == 1)
    }

    @Test func aFrameWithoutThePointerOnlyBreathes() {
        var state = PicksIconState()
        state.advance(pointer: nil, size: CGSize(width: 40, height: 40), isPressed: true, unit: 3, dt: 0.02, motion: 1)
        #expect(state.excitement == 0)
        #expect(state.mood == 0)
        #expect(state.lean == .zero)
        #expect(abs(state.press - (1 - exp(-1))) < 1e-6)
        #expect(abs(state.phase - 0.02 / 3) < 1e-6)
    }

    @Test func aFrameWithThePointerOnTheIconExcitesIt() {
        var state = PicksIconState()
        state.advance(pointer: CGPoint(x: 20, y: 20), size: CGSize(width: 40, height: 40), isPressed: false, unit: 3, dt: 0.01, motion: 1)
        #expect(state.excitement == 1)
        #expect(abs(state.scaling - (1 - exp(-1))) < 1e-6)
        #expect(state.lean == .zero)   // no direction to lean in
    }

    // MARK: - Outline

    @Test func extentAddsTheHarmonicsAmplitudes() {
        var outline = FourierOutline(harmonicCount: 3)
        outline.cosines = [-0.1, 0.3, 0, 0]
        outline.sines = [0.5, 0.4, 0, 0.2]
        #expect(abs(outline.extent - (0.1 + 0.5 + 0.2)) < 1e-6)   // the constant has no sine
    }

    @Test func restingSparkHasFourPoints() {
        let resting = PicksIconOutline.resting
        #expect(abs(resting.offset(at: 0) - 0.15) < 1e-6)
        #expect(abs(resting.offset(at: .pi / 2) - 0.15) < 1e-5)
        #expect(abs(resting.offset(at: .pi / 4) + 0.09) < 1e-5)
        #expect(abs(PicksIconOutline.reach.resting - 1.15) < 1e-6)
        #expect(PicksIconOutline.reach.breathing > 0)
    }

    @Test func sampleLoopsThroughTheKeyframes() {
        let keyframes = PicksIconOutline.keyframes
        #expect(PicksIconOutline.sample(atPhase: 0) == keyframes[0])
        #expect(PicksIconOutline.sample(atPhase: 1) == keyframes[0])
        let halfway = PicksIconOutline.sample(atPhase: 0.5 / Float(keyframes.count))
        let expected = keyframes[0].interpolated(to: keyframes[1], by: 0.5)
        for (value, target) in zip(halfway.cosines, expected.cosines) {
            #expect(abs(value - target) < 1e-5)
        }
        let last = PicksIconOutline.sample(atPhase: 0.999_999)
        #expect(abs(last.cosines[4] - keyframes[0].cosines[4]) < 1e-3)
    }

    @Test func shapeBlendsTheMotionIntoRest() {
        #expect(PicksIconOutline.shape(atPhase: 0.3, amplitude: 0, modeCount: 10) == PicksIconOutline.resting)
        let full = PicksIconOutline.shape(atPhase: 0.3, amplitude: 1, modeCount: 10)
        let sample = PicksIconOutline.sample(atPhase: 0.3)
        for (value, target) in zip(full.cosines + full.sines, sample.cosines + sample.sines) {
            #expect(abs(value - target) < 1e-6)
        }
        // Below the mode count only the pulse of the whole shape is left.
        let pulse = PicksIconOutline.shape(atPhase: 0.3, amplitude: 1, modeCount: 0)
        #expect(pulse.cosines[0] == PicksIconOutline.sample(atPhase: 0.3).cosines[0])
        #expect(Array(pulse.cosines.dropFirst()) == Array(PicksIconOutline.resting.cosines.dropFirst()))
    }
}
