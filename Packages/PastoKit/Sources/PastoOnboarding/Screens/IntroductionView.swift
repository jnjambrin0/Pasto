import PastoUI
import SwiftUI

/// The welcome's first step: what Pasto is, and a button to go on. The button is the app's
/// filled one.
struct IntroductionView: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingStep(illustration: .intro, title: OnboardingStrings.introTitle, subtitle: OnboardingStrings.introSubtitle) {
            EmptyView()
        } buttons: {
            Button(OnboardingStrings.getStarted, action: onContinue)
                .buttonStyle(PastoButtonStyle(.filled))
                .keyboardShortcut(.defaultAction)
                .focusEffectDisabled()
        }
    }
}
