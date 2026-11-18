import SwiftUI

/// The rounded card the rows sit on.
struct OnboardingCard<Rows: View>: View {
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            rows
        }
        .frame(width: OnboardingMetrics.cardWidth)
        .background(
            Color.primary.opacity(OnboardingMetrics.cardFillOpacity),
            in: RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
        )
    }
}
