import SwiftUI

/// The layout every welcome step shares: its illustration across the top, then the
/// title, the subtitle, what the step shows, an optional footnote, and the buttons. A step is as
/// tall as what it shows and the window follows it, so that a step with little to say leaves
/// no empty band above its buttons.
struct OnboardingStep<Content: View, Buttons: View>: View {
    let illustration: OnboardingIllustration.Kind
    let title: String
    let subtitle: String
    var footnote: String?
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            // Edge to edge, so square-cornered: the window rounds the top.
            OnboardingIllustration(illustration, cornerRadius: 0)
                .frame(width: OnboardingMetrics.illustrationSize.width, height: OnboardingMetrics.illustrationSize.height)
                .clipped()
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: OnboardingMetrics.titlePointSize, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, OnboardingMetrics.titleBottomSpacing)
                Text(subtitle)
                    .font(.system(size: OnboardingMetrics.subtitlePointSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
                    .padding(.top, OnboardingMetrics.contentTopSpacing)
                if let footnote {
                    Text(footnote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, OnboardingMetrics.contentBottomSpacing)
                }
                HStack(spacing: OnboardingMetrics.buttonSpacing) {
                    buttons
                }
                .padding(.top, OnboardingMetrics.buttonsTopSpacing)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: OnboardingMetrics.textMaxWidth)
            .padding(.top, OnboardingMetrics.bodyTopPadding)
            .padding(.bottom, OnboardingMetrics.bodyBottomPadding)
        }
        .frame(width: OnboardingMetrics.contentSize.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
    }
}
