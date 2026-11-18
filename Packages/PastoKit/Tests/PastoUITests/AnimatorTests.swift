import Testing
@testable import PastoUI

/// Reduce Motion: a motion goes straight to its end, anything else keeps its duration, and with
/// the setting off nothing changes.
@Suite struct AnimatorTests {
    @Test func aMotionHasNoDurationWhileMotionIsReduced() {
        #expect(Animator.duration(0.25, isMotion: true, reducesMotion: true) == 0)
    }

    @Test func whatIsNoMotionKeepsItsDurationWhileMotionIsReduced() {
        #expect(Animator.duration(0.25, isMotion: false, reducesMotion: true) == 0.25)
    }

    @Test func withTheSettingOffEveryDurationStays() {
        #expect(Animator.duration(0.25, isMotion: true, reducesMotion: false) == 0.25)
        #expect(Animator.duration(0.25, isMotion: false, reducesMotion: false) == 0.25)
    }
}
