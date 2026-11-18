import CoreGraphics
import Foundation
import simd
import Testing
@testable import PastoMainPanel

@Suite struct GlowDynamicsTests {
    let tuning = GlowTuning.standard

    @Test func uniformsAreTwentySixPackedFloats() {
        #expect(MemoryLayout<GlowUniforms>.stride == 26 * 4)
        #expect(MemoryLayout<SIMD2<Float>>.stride == 8)
        #expect(MemoryLayout<SIMD4<Float>>.stride == 16)
    }

    @Test func frameStepIsZeroFirstAndCappedAfterAPause() {
        #expect(FrameDrivenView.frameInterval(now: 5, lastTick: 0) == 0)
        #expect(abs(FrameDrivenView.frameInterval(now: 5.01, lastTick: 5) - 0.01) < 1e-6)
        #expect(FrameDrivenView.frameInterval(now: 9, lastTick: 5) == Float(1.0 / 30))
    }

    @Test func startsAtRestInTheClosedScene() {
        let state = GlowState(tuning: tuning)
        #expect(state.sceneShown == .closed)
        #expect(state.levels == tuning.closed.levels)
        #expect(state.pointer == GlowState.farPointer)
        #expect(state.lights.count == GlowTuning.lightCount)
    }

    @Test func lightAppearanceSwapsFourValues() {
        let targets = tuning.loading.targets(isDark: false)
        #expect(targets.bandAlpha == 1)
        #expect(targets.bandIntensity == 1.5)
        #expect(targets.fillAlpha == 0.5)
        #expect(targets.fillIntensity == 1)
        #expect(targets.noiseSpeed == 6)
        #expect(tuning.loading.targets(isDark: true) == tuning.loading.levels)
    }

    // MARK: - Scenes

    @Test func enteringTheBurstStartsItUnlessMotionIsReduced() {
        var state = GlowState(tuning: tuning)
        state.show(.loading, at: 5, motion: 1, tuning: tuning)
        #expect(state.burstStart == 5)
        #expect(state.waveReleased == nil)

        var reduced = GlowState(tuning: tuning)
        reduced.show(.loading, at: 5, motion: 0, tuning: tuning)
        #expect(reduced.burstStart == nil)
        #expect(reduced.sceneShown == .loading)
    }

    @Test func leavingTheBurstReleasesTheSwellOnce() {
        var state = GlowState(tuning: tuning)
        state.show(.loading, at: 5, motion: 1, tuning: tuning)
        state.show(.open, at: 6.5, motion: 1, tuning: tuning)
        #expect(state.waveReleased == 6.5)
        state.show(.closed, at: 8, motion: 1, tuning: tuning)
        #expect(state.waveReleased == 6.5)
        #expect(state.burstStart == 5)
    }

    // MARK: - Springs

    @Test func springStepIsSemiImplicitEuler() {
        var state = GlowState(tuning: tuning)
        var targets = state.levels
        targets.bandAlpha += 1
        state.stepSprings(toward: targets, arrival: 10, dt: 0.01)
        // a = 10² × 1 − 1.7 × 10 × 0 = 100; v = 1; x += 0.01.
        #expect(abs(state.velocities.bandAlpha - 1) < 1e-5)
        #expect(abs(state.levels.bandAlpha - (tuning.closed.levels.bandAlpha + 0.01)) < 1e-5)
        #expect(state.velocities.focus == 0)
    }

    @Test func springsHaveAMinimumArrival() {
        var slow = GlowState(tuning: tuning)
        var floored = GlowState(tuning: tuning)
        var targets = slow.levels
        targets.fillDepth += 1
        slow.stepSprings(toward: targets, arrival: 0.1, dt: 0.1)
        floored.stepSprings(toward: targets, arrival: 0.5, dt: 0.1)
        #expect(slow.levels == floored.levels)
    }

    @Test func springsSettleOnTheScene() {
        var state = GlowState(tuning: tuning)
        let target = tuning.open
        for _ in 0..<600 {
            state.stepSprings(toward: target.levels, arrival: target.arrival, dt: 1.0 / 120)
        }
        for keyPath in GlowLevels.springs {
            #expect(abs(state.levels[keyPath: keyPath] - target.levels[keyPath: keyPath]) < 1e-3)
        }
    }

    // MARK: - Noise, colour and lights

    @Test func noiseDriftsWithTheNoiseSpeed() {
        var state = GlowState(tuning: tuning)
        state.stepSprings(toward: tuning.loading.levels, arrival: 10, dt: 0.05)
        let speed = state.levels.noiseSpeed
        state.advanceNoise(dt: 0.5, motion: 1)
        #expect(abs(state.noiseOffset.x - 0.007 * 0.5 * speed) < 1e-6)
        #expect(abs(state.noiseOffset.y + 0.011 * 0.5 * speed) < 1e-6)
        #expect(abs(state.noiseOffset.z - 0.06 * 0.5 * speed) < 1e-6)
        #expect(abs(state.colourTime - 0.5 * (0.3 + 0.7 * speed)) < 1e-5)
    }

    @Test func reducedMotionStillsTheNoiseAndSlowsTheColours() {
        var state = GlowState(tuning: tuning)
        state.stepSprings(toward: tuning.loading.levels, arrival: 10, dt: 0.05)
        state.advanceNoise(dt: 1, motion: 0)
        #expect(state.noiseOffset == .zero)
        #expect(abs(state.colourTime - 0.3) < 1e-6)
    }

    @Test func lightsStartOnTheirOrbits() {
        var state = GlowState(tuning: tuning)
        state.placeLights(on: tuning.orbits)
        for (light, orbit) in zip(state.lights, tuning.orbits) {
            let angle = orbit.phase * .pi / 180
            let radius = orbit.radius + orbit.breath * sin(orbit.phase)
            #expect(abs(light.x - cos(angle) * radius) < 1e-5)
            #expect(abs(light.y - sin(angle) * radius) < 1e-5)
        }
    }

    @Test func huesRepeatOverTheLights() {
        let hues = GlowState.lightHues(tuning.hues)
        #expect(hues.count == 11)
        #expect(hues[0] == SIMD4(tuning.hues[0], 1))
        #expect(hues[3] == hues[0])
        #expect(hues[10] == SIMD4(tuning.hues[1], 1))
    }

    // MARK: - Pointer

    @Test func pointerOutsideTheViewIsFarAway() {
        let size = CGSize(width: 1000, height: 300)
        #expect(GlowState.pointerTarget(location: nil, size: size) == GlowState.farPointer)
        #expect(GlowState.pointerTarget(location: CGPoint(x: -1, y: 10), size: size) == GlowState.farPointer)
        #expect(GlowState.pointerTarget(location: CGPoint(x: 10, y: 10), size: .zero) == GlowState.farPointer)
    }

    @Test func pointerIsNormalisedByTheWidth() {
        let target = GlowState.pointerTarget(location: CGPoint(x: 750, y: 300), size: CGSize(width: 1000, height: 400))
        #expect(abs(target.x - 0.25) < 1e-6)
        #expect(abs(target.y - 0.1) < 1e-6)   // (0.75 − 0.5) × 400 / 1000
    }

    @Test func pointerFollowsWithALag() {
        var state = GlowState(tuning: tuning)
        state.followPointer(to: .zero, dt: 0.1, lag: 0.1)
        let expected = GlowState.farPointer * exp(-1)
        #expect(abs(state.pointer.x - expected.x) < 1e-5)
        state.followPointer(to: SIMD2(5, 5), dt: 0, lag: 0.1)
        #expect(abs(state.pointer.x - expected.x) < 1e-5)
    }

    // MARK: - Swell

    @Test func noSwellWithoutABurst() {
        let state = GlowState(tuning: tuning)
        #expect(state.wave(at: 100, tuning: tuning) == 0)
    }

    @Test func swellRisesQuicklyHoldsAndFalls() {
        var state = GlowState(tuning: tuning)
        state.show(.loading, at: 0, motion: 1, tuning: tuning)
        #expect(abs(state.wave(at: 0, tuning: tuning)) < 1e-6)
        // Back easing: 1 + 2.70158·p³ + 1.70158·p² with p = 0.2 − 1.
        #expect(abs(state.wave(at: 0.2, tuning: tuning) - 0.705_810) < 1e-5)
        // Its overshoot is cut off: the falling curve stands at 1 until the release.
        #expect(state.wave(at: 0.8, tuning: tuning) == 1)
        #expect(abs(state.wave(at: 1, tuning: tuning) - 1) < 1e-6)
        #expect(abs(state.wave(at: 1.9, tuning: tuning) - 1) < 1e-6)
        // Released after its life (rise 1 + life 1): smoothstep down over 0.5 s.
        #expect(abs(state.wave(at: 2.25, tuning: tuning) - 0.5) < 1e-6)
        #expect(state.wave(at: 2.5, tuning: tuning) == 0)
    }

    @Test func leavingTheSceneReleasesTheSwellEarly() {
        var state = GlowState(tuning: tuning)
        state.show(.loading, at: 0, motion: 1, tuning: tuning)
        state.show(.open, at: 0.5, motion: 1, tuning: tuning)
        #expect(state.wave(at: 1, tuning: tuning) == 0)
        #expect(abs(state.wave(at: 0.75, tuning: tuning) - 0.5) < 0.1)
    }

    // MARK: - Uniforms

    @Test func burstTimeIsCappedAndStandsWithoutABurst() {
        var state = GlowState(tuning: tuning)
        let size = CGSize(width: 1000, height: 300)
        #expect(uniforms(state, at: 3, size: size).burstTime == 10)
        state.show(.loading, at: 2, motion: 1, tuning: tuning)
        #expect(uniforms(state, at: 3.5, size: size).burstTime == 1.5)
        #expect(uniforms(state, at: 30, size: size).burstTime == 10)
    }

    @Test func excitementStirsTheEmberOnlyWhileFocused() {
        let state = GlowState(tuning: tuning)   // closed: focus 1
        let size = CGSize(width: 1000, height: 300)
        let calm = uniforms(state, at: 0, size: size, excitement: 0)
        let stirred = uniforms(state, at: 0, size: size, excitement: 1)
        #expect(stirred.bandAmount == calm.bandAmount * 1.25)
        #expect(stirred.bandIntensity == calm.bandIntensity * 1.4)
        #expect(stirred.emberReach == 80 * 1.25)
        #expect(calm.emberReach == 80)

        var open = GlowState(tuning: tuning)
        for _ in 0..<600 {
            open.stepSprings(toward: tuning.open.levels, arrival: tuning.open.arrival, dt: 1.0 / 120)
        }
        let unfocused = uniforms(open, at: 0, size: size, excitement: 1)
        #expect(abs(unfocused.emberReach - 80) < 0.1)
    }

    @Test func swellDeepensTheFill() {
        var state = GlowState(tuning: tuning)
        state.show(.loading, at: 0, motion: 1, tuning: tuning)
        let swollen = uniforms(state, at: 1, size: CGSize(width: 1000, height: 300))
        #expect(swollen.fillDepth == 2)        // max(closed fill depth 1, swell 1 × 2)
        #expect(swollen.fillAlpha == 0.25)     // the swell adds no alpha
    }

    @Test func originIsNormalisedLikeThePointer() {
        let state = GlowState(tuning: tuning)
        let result = uniforms(state, at: 0, size: CGSize(width: 1000, height: 400), origin: CGPoint(x: 0, y: 0))
        #expect(result.originX == -0.5)
        #expect(abs(result.originY + 0.2) < 1e-6)
        #expect(result.mouseX == 9)
        #expect(result.mouseWeight == 0)
    }

    // MARK: - Noise texture

    @Test func noiseTilesAcrossTheVolume() {
        let octave = GlowNoise.octaves[0]
        let start = GlowNoise.value(at: SIMD3(0, 0.2, 0.4), octave: octave)
        let wrapped = GlowNoise.value(at: SIMD3(0.999_999, 0.2, 0.4), octave: octave)
        #expect(abs(start - wrapped) < 1e-3)
    }

    @Test func noiseIsNormalisedAroundTheMiddle() {
        let bytes = GlowNoise.normalised([1, 2, 3, 4, 5, 6, 7, 8])
        let mean = Float(bytes.reduce(0) { $0 + Int($1) }) / Float(bytes.count)
        #expect(abs(mean - 127.5) < 1)
        // One deviation (≈ 2.29) is 0.15 of the range.
        #expect(bytes.max()! - bytes.min()! < 120)
        #expect(GlowNoise.normalised([]) == [])
    }

    private func uniforms(
        _ state: GlowState,
        at now: CFTimeInterval,
        size: CGSize,
        excitement: Float = 0,
        origin: CGPoint = CGPoint(x: 32, y: 30)
    ) -> GlowUniforms {
        state.uniforms(at: now, size: size, scale: 2, cornerRadius: 26, origin: origin, excitement: excitement, tuning: tuning)
    }
}
