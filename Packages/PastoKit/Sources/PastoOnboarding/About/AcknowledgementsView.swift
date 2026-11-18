import SwiftUI

/// The third-party licenses, one after another: the name, its details and the license text as
/// published, in a monospaced face so its own line breaks and indents hold.
struct AcknowledgementsView: View {
    let acknowledgements: Acknowledgements

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AboutMetrics.acknowledgementsEntrySpacing) {
                Text(OnboardingStrings.acknowledgementsIntroduction)
                    .font(.body)
                ForEach(acknowledgements.entries) { entry in
                    VStack(alignment: .leading, spacing: AboutMetrics.acknowledgementsLineSpacing) {
                        Text(entry.name)
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                        if !entry.details.isEmpty {
                            Text(entry.details)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.license)
                            .font(.system(.caption, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AboutMetrics.acknowledgementsInset)
        }
    }
}
