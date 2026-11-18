import SwiftUI

/// The window that asks for Accessibility or pasteboard access. The welcome shows the same model
/// with its own step layout (`PastoOnboarding`).
struct AccessRequestView: View {
    let model: AccessRequestModel

    var body: some View {
        PermissionTemplate(
            isGranted: model.isAccessEnabled,
            title: title,
            subtitle: subtitle,
            illustration: illustration
        ) {
            PermissionButton(
                title: model.primaryActionTitle,
                style: mainButtonStyle,
                action: model.performPrimaryAction
            )
            .keyboardShortcut(.defaultAction)
        }
        .onAppear(perform: model.startObserving)
        .onDisappear(perform: model.stopObserving)
    }

    /// Accessibility uses the app's own capsules; the pasteboard window, the system's buttons.
    private var mainButtonStyle: PermissionButton.Style {
        switch model.permission {
        case .accessibility: .filled
        case .pasteboard: .system
        }
    }

    private var title: String {
        model.permission.title
    }

    private var subtitle: String {
        model.permission.subtitle
    }

    private var illustration: PermissionIllustration.Kind {
        switch model.permission {
        case .accessibility: .accessibility
        case .pasteboard: .pasteboard
        }
    }
}
