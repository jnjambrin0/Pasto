import AppKit
import PastoCore
import PastoFoundation
import PastoInput
import PastoPermissions
import SwiftUI

/// Shows the onboarding window and tells when the user has gone through it.
///
/// On a first launch the window has no buttons and refuses to close: the only way out is
/// forward. Shown again from Help › Getting Started, it starts from the first screen, shows the
/// settings as they are, and can be closed at any point.
public final class OnboardingWindowPresenter: NSObject, NSWindowDelegate {
    private let config: ConfigStore
    private let reader: StoreReader
    private let writer: StoreWriter
    private let hotKeys: HotKeyCenter
    private let suggestions: OnboardingSuggestions?
    private let isReplay: Bool
    private let resumesReplay: Bool
    private var window: NSWindow?
    private var hasSizedWindow = false
    private var steps: OnboardingSteps?
    private var onFinish: (() -> Void)?

    /// When the last step's button was pressed, to time the hand-over to the panel.
    public private(set) var finishInstant: ContinuousClock.Instant?

    /// - Parameters:
    ///   - hotKeys: Paused while the activation shortcut is being recorded.
    ///   - suggestions: On a Mac that can run suggestions, what their step needs; nil leaves the
    ///     step out.
    ///   - isReplay: Shown again from the Help menu, not as part of a first launch.
    ///   - resumesReplay: Shown again after System Settings quit and reopened Pasto in the middle
    ///     of a replay: it goes back to the step it was on instead of the first.
    public init(
        config: ConfigStore,
        reader: StoreReader,
        writer: StoreWriter,
        hotKeys: HotKeyCenter,
        suggestions: OnboardingSuggestions?,
        isReplay: Bool = false,
        resumesReplay: Bool = false
    ) {
        self.config = config
        self.reader = reader
        self.writer = writer
        self.hotKeys = hotKeys
        self.suggestions = suggestions
        self.isReplay = isReplay
        self.resumesReplay = resumesReplay
    }

    /// Runs onboarding from where it was left, or from the start. Returns once the last screen
    /// is done — or, shown again, the window was closed — the window is gone and what the last
    /// step changed is in place.
    public func run() async {
        if isReplay, !resumesReplay {
            // From the first screen, whatever an earlier replay closed halfway left saved.
            config.set(JSONConfigValue(nil), for: .onboardingState)
        }
        NSApp.activate(ignoringOtherApps: true)
        await withCheckedContinuation { continuation in
            onFinish = { continuation.resume() }
            show { [weak self] in self?.finish() }
        }
        window?.delegate = nil
        window?.close()
        window = nil
        // The login item is registered off the main thread; the panel waits for it, so that the
        // notice cards seeded next see it.
        await steps?.quickStart.loginItemUpdate?.value
        steps = nil
    }

    private func finish() {
        finishInstant = .now
        let onFinish = onFinish
        self.onFinish = nil
        onFinish?()
    }

    private func show(onFinish: @escaping () -> Void) {
        let flow = OnboardingFlowModel(
            screens: OnboardingScreen.list(offersSuggestions: suggestions != nil),
            config: config,
            onFinish: onFinish
        )
        let steps = makeSteps(flow: flow)
        self.steps = steps

        let window = ChromelessWindow.make(isClosable: true, animationBehavior: .alertPanel)
        // Not shown (the title bar is hidden), but VoiceOver and Mission Control name the window.
        window.title = OnboardingStrings.welcomeWindowTitle
        // Before the content goes in: its first measurement sizes the window.
        self.window = window
        ChromelessWindow.setContent(
            OnboardingContainerView(flow: flow, steps: steps) { [weak self] in self?.resize(toContentHeight: $0) },
            of: window
        )
        window.delegate = self
        // Shown again, it can be closed like any window.
        let hiddenButtons: [NSWindow.ButtonType] = isReplay ? [.miniaturizeButton, .zoomButton] : [.closeButton, .miniaturizeButton, .zoomButton]
        for button in hiddenButtons {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Activation is a request the system may turn down when another app is in use; the
        // welcome window must be seen all the same.
        window.orderFrontRegardless()
        self.window = window
    }

    /// The window is as tall as the step on show. Its top edge stays where it is, as the
    /// illustration does; the first measurement, which comes before anything has been seen,
    /// places the window in the middle of the screen instead.
    private func resize(toContentHeight height: CGFloat) {
        guard let window else { return }
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: OnboardingMetrics.contentSize.width, height: height))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if hasSizedWindow {
            window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        } else {
            hasSizedWindow = true
            window.setFrame(frame, display: true)
            window.center()
        }
    }

    /// Every step's state, made now, while the first step is on show.
    private func makeSteps(flow: OnboardingFlowModel) -> OnboardingSteps {
        let quickStart = QuickStartModel(config: config, reader: reader, writer: writer, hotKeys: hotKeys) {
            flow.advance(from: .setup)
        }
        if isReplay {
            quickStart.loadLoginItemState()
        }
        return OnboardingSteps(
            accessibility: .onboardingStep(.accessibility) { flow.advance(from: .directPaste) },
            pasteboard: .onboardingStep(.pasteboard) { flow.advance(from: .pasteboardAccess) },
            suggestions: suggestions.map { suggestions in
                SuggestionsStepModel(config: config, suggestions: suggestions, origin: isReplay ? .gettingStarted : .onboarding) {
                    flow.advance(from: .suggestions)
                }
            },
            quickStart: quickStart
        )
    }

    /// On a first launch ⌘W has nothing to close here; shown again, it closes the window.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        isReplay
    }

    /// Closing a replay ends it. A first launch only ends on its last screen: a window closed
    /// as Pasto quits halfway must not count as onboarding done.
    public func windowWillClose(_ notification: Notification) {
        guard isReplay else { return }
        finish()
    }
}
