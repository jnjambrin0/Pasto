import AppKit
import SwiftUI

/// The content of the About window: icon, name and version at the top, and the legal lines
/// centred below them: the copyright, the warranty notice and the button to the third-party
/// licenses.
struct AboutView: View {
    private static let fallbackName = "Pasto"

    let showAcknowledgements: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: AboutMetrics.spacing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: AboutMetrics.iconSide, height: AboutMetrics.iconSide)
                    .accessibilityHidden(true)
                VStack(spacing: AboutMetrics.nameVersionSpacing) {
                    Text(name)
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    if let version {
                        Text(OnboardingStrings.version(version))
                            .font(.body)
                    }
                }
            }
            Spacer(minLength: AboutMetrics.spacing)
            VStack(spacing: AboutMetrics.legalSpacing) {
                Text(OnboardingStrings.aboutCopyright)
                    .font(.body)
                Text(OnboardingStrings.aboutDisclaimer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(OnboardingStrings.acknowledgements, action: showAcknowledgements)
                    .buttonStyle(.link)
                    .font(.callout)
            }
            .multilineTextAlignment(.center)
            .frame(width: AboutMetrics.copyrightWidth)
            Spacer(minLength: AboutMetrics.spacing)
        }
        .textSelection(.enabled)
        .padding(AboutMetrics.inset)
        .frame(width: AboutMetrics.contentSize.width, height: AboutMetrics.contentSize.height)
        .padding(.top, AboutMetrics.titleBarHeight)
    }

    private var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? Self.fallbackName
    }

    private var version: String? {
        AboutVersion.text(
            shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
