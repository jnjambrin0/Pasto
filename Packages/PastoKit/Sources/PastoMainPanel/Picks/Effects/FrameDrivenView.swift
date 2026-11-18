import AppKit
import PastoUI
import QuartzCore

/// A view that draws a new frame on every refresh of its display while it can be seen: the base
/// of the suggestions glow and of the animated suggestions icon.
///
/// The display link exists while the view is in a window and is paused while the view, one of
/// its ancestors or the whole window is out of sight, so nothing is computed for a closed panel.
class FrameDrivenView: LayerBackedView {
    /// The longest step a frame advances the animation by, so that a frame arriving late — or
    /// the first one after a pause — does not make it jump.
    nonisolated static let maximumFrameInterval: CFTimeInterval = 1.0 / 30

    private var displayLink: CADisplayLink?
    /// When the previous frame was drawn; 0 until the first one.
    private var lastTick: CFTimeInterval = 0
    private var occlusionObserver: (any NSObjectProtocol)?

    isolated deinit {
        displayLink?.invalidate()
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }

    /// Draws one frame. `now` is the media time, `dt` how far to advance the animation (0 on the
    /// very first frame) and `motion` 0 when the user asked to reduce motion, 1 otherwise.
    func render(now: CFTimeInterval, dt: Float, motion: Float) {}

    /// The step of a frame drawn at `now` after one drawn at `lastTick` (0: none yet).
    nonisolated static func frameInterval(now: CFTimeInterval, lastTick: CFTimeInterval) -> Float {
        lastTick == 0 ? 0 : Float(min(now - lastTick, maximumFrameInterval))
    }

    // MARK: - Display link

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        guard let newWindow else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: newWindow, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePausedState() }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if window != nil {
            // The link follows the screen the view is on, so it always ticks at that display's rate.
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        updatePausedState()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updatePausedState()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updatePausedState()
    }

    private func updatePausedState() {
        let isWindowVisible = window?.occlusionState.contains(.visible) ?? false
        displayLink?.isPaused = isHiddenOrHasHiddenAncestor || !isWindowVisible
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = Self.frameInterval(now: now, lastTick: lastTick)
        lastTick = now
        let motion: Float = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1
        render(now: now, dt: dt, motion: motion)
    }
}
