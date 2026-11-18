import SwiftUI

/// The window that asks for screen recording access, which suggestions need. Once Pasto comes
/// back granted, the same window carries out the capture check that gets macOS's confirmation
/// over with, and shows the check mark when it has.
struct ScreenRecordingAccessView: View {
    let model: ScreenRecordingAccessModel

    var body: some View {
        Group {
            if model.isGranted {
                PermissionTemplate(
                    isGranted: model.confirmation == .confirmed,
                    title: PermissionStrings.screenCaptureCheckTitle,
                    subtitle: PermissionStrings.screenCaptureCheckSubtitle,
                    illustration: .suggestions,
                    footnote: model.confirmation == .failed ? PermissionStrings.screenCaptureCheckFailed : nil
                ) {
                    PermissionButton(
                        title: model.confirmation == .running ? PermissionStrings.checking : PermissionStrings.continueAction,
                        style: .filled
                    ) {
                        Task { await model.confirm() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.confirmation == .running)
                }
            } else {
                PermissionTemplate(
                    title: PermissionStrings.screenRecordingTitle,
                    subtitle: PermissionStrings.screenRecordingSubtitle,
                    illustration: .suggestions,
                    footnote: model.opensSystemSettings ? PermissionStrings.quitAndReopenHint : nil
                ) {
                    PermissionButton(title: PermissionStrings.openSystemSettings, style: .filled, action: model.requestAccess)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear(perform: model.startObserving)
        .onDisappear(perform: model.stopObserving)
    }
}
