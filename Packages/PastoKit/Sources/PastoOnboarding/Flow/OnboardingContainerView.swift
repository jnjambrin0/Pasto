import AppKit
import PastoPermissions
import SwiftUI

/// The content of the onboarding window: one step at a time, each with a way forward and no
/// way back.
struct OnboardingContainerView: View {
    let flow: OnboardingFlowModel
    let steps: OnboardingSteps
    /// Called with the height of the step on show, whenever it changes: the window follows it.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var height = OnboardingMetrics.contentSize.height

    /// "Reduce motion": screens cross-fade in place instead of sliding across the window.
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        ZStack(alignment: .top) {
            screen
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: StepHeights.self, value: [flow.current: geometry.size.height])
                })
                // Inside the identity, so that it runs for every step that comes in.
                .onAppear { [current = flow.current] in flow.screenDidAppear(current) }
                .id(flow.current)
                .transition(
                    reducesMotion
                        ? .opacity
                        : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                )
        }
        .frame(width: OnboardingMetrics.contentSize.width, height: height, alignment: .top)
        .clipped()
        // While one step slides out and the next slides in both are measured; the window takes
        // the height of the one coming in.
        .onPreferenceChange(StepHeights.self) { heights in
            guard let measured = heights[flow.current], measured > 0, measured != height else { return }
            height = measured
            onHeightChange(measured)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(
            .easeInOut(duration: reducesMotion ? OnboardingMetrics.reducedMotionTransitionDuration : OnboardingMetrics.transitionDuration),
            value: flow.current
        )
        // The screen changes under VoiceOver's cursor: it says which one comes.
        .onChange(of: flow.current) { _, screen in
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: steps.title(of: screen), .priority: NSAccessibilityPriorityLevel.high.rawValue]
            )
        }
    }

    @ViewBuilder private var screen: some View {
        switch flow.current {
        case .intro: IntroductionView { flow.advance(from: .intro) }
        case .directPaste: PermissionStepView(model: steps.accessibility)
        case .pasteboardAccess: PermissionStepView(model: steps.pasteboard)
        case .suggestions:
            if let suggestions = steps.suggestions {
                SuggestionsStepView(model: suggestions)
            }
        case .setup: QuickStartView(model: steps.quickStart)
        }
    }
}

/// The height each step on screen asks for.
private struct StepHeights: PreferenceKey {
    static let defaultValue: [OnboardingScreen: CGFloat] = [:]

    static func reduce(value: inout [OnboardingScreen: CGFloat], nextValue: () -> [OnboardingScreen: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
