import SwiftUI

/// A row of a welcome card: what it is about on the leading side, a control or a state on the
/// trailing one, and a divider under every row but the last.
struct OnboardingRow<Leading: View, Trailing: View>: View {
    var isLast = false
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, OnboardingMetrics.rowVerticalPadding)
                Spacer(minLength: OnboardingMetrics.rowHorizontalPadding)
                trailing
            }
            .frame(maxWidth: .infinity)
            if !isLast {
                Divider()
            }
        }
        .padding(.horizontal, OnboardingMetrics.rowHorizontalPadding)
    }
}

extension OnboardingRow where Leading == OnboardingRowText {
    /// A row with a title, a subtitle and, if there is one, a note under them.
    init(title: String, subtitle: String, note: String? = nil, isLast: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.init(isLast: isLast, leading: { OnboardingRowText(title: title, subtitle: subtitle, note: note) }, trailing: trailing)
    }
}

/// The texts of a row: title, subtitle and an optional note saying why the control holds what
/// it holds.
struct OnboardingRowText: View {
    let title: String
    let subtitle: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: OnboardingMetrics.rowTextSpacing) {
            Text(title)
                .font(.body)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let note {
                Label(note, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
