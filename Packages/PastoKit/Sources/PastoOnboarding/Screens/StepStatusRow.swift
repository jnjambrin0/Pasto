import SwiftUI

/// A row that says where a permission stands: a green check once it is done, an empty circle
/// while it waits for the user, a spinner while Pasto is at it, and what is missing in words.
struct StepStatusRow: View {
    enum State: Equatable {
        case done
        case pending
        case working
        case problem
    }

    let state: State
    let title: String
    let detail: String
    var isLast = false

    var body: some View {
        OnboardingRow(isLast: isLast) {
            HStack(alignment: .firstTextBaseline, spacing: OnboardingMetrics.statusSymbolSpacing) {
                symbol
                    .font(.system(size: OnboardingMetrics.statusSymbolPointSize))
                    .frame(width: OnboardingMetrics.statusSymbolPointSize + 4)
                OnboardingRowText(title: title, subtitle: detail)
            }
        } trailing: {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityState)
    }

    @ViewBuilder private var symbol: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .pending:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .working:
            ProgressView().controlSize(.small)
        case .problem:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    private var accessibilityState: String {
        switch state {
        case .done: OnboardingStrings.stateDone
        case .pending, .problem: OnboardingStrings.statePending
        case .working: OnboardingStrings.stateWorking
        }
    }
}
