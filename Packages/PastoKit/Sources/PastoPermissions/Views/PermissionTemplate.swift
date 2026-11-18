import AppKit
import PastoUI
import SwiftUI

/// The layout every screen that asks for one permission shares: the app icon, a title, a
/// subtitle, a picture and a row of buttons, centred; or just a green check mark once the
/// permission is granted.
struct PermissionTemplate<Buttons: View>: View {
    var isGranted = false
    let title: String
    let subtitle: String
    let illustration: PermissionIllustration.Kind
    /// A line under the buttons: what comes next, or what went wrong.
    var footnote: String?
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if isGranted {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: PermissionMetrics.grantedSymbolPointSize))
                    .foregroundStyle(.green)
                    .accessibilityLabel(PermissionStrings.accessGranted)
            } else {
                request
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var request: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: PermissionMetrics.iconSide, height: PermissionMetrics.iconSide)
            .padding(.bottom, PermissionMetrics.iconBottomSpacing)
            .accessibilityHidden(true)
        Text(title)
            .font(.title.bold())
            .accessibilityAddTraits(.isHeader)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: PermissionMetrics.textMaxWidth)
            .padding(.bottom, PermissionMetrics.titleBottomSpacing)
        Text(subtitle)
            .font(.body)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: PermissionMetrics.textMaxWidth)
            .padding(.bottom, PermissionMetrics.subtitleBottomSpacing)
        PermissionIllustration(illustration)
            .frame(width: PermissionMetrics.illustrationSize.width, height: PermissionMetrics.illustrationSize.height)
            .clipShape(RoundedRectangle(cornerRadius: PermissionMetrics.illustrationCornerRadius, style: .continuous))
            .padding(.bottom, PermissionMetrics.illustrationBottomSpacing)
        HStack(spacing: PermissionMetrics.buttonSpacing) {
            buttons
        }
        if let footnote {
            Text(footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: PermissionMetrics.textMaxWidth)
                .padding(.top, PermissionMetrics.footnoteTopSpacing)
        }
    }
}

/// A button of the template's row, its label with a little air on both sides. Accessibility
/// and screen recording use the app's own filled capsule; the pasteboard window uses the system's
/// buttons at their large size. The windows have a single button: "Not Now" belongs to the
/// welcome's steps, which draw their own.
struct PermissionButton: View {
    enum Style {
        case filled
        case system
    }

    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Text(title).padding(.horizontal, PermissionMetrics.buttonLabelHorizontalPadding)
        }
        switch style {
        case .filled: button.buttonStyle(PastoButtonStyle(.filled))
        case .system: button.controlSize(.large)
        }
    }
}
