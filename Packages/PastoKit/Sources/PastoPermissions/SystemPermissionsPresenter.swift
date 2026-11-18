import AppKit
import PastoFoundation
import SwiftUI

/// Presents the permission windows.
///
/// The modal ones block until the user is done, and must not be asked for while another modal
/// window is up: callers check `NSApp.modalWindow` first.
@MainActor
public final class SystemPermissionsPresenter {
    private let config: ConfigStore
    private var screenRecordingWindow: PermissionWindowController?

    public init(config: ConfigStore) {
        self.config = config
    }

    /// Asks whether to grant Accessibility access or only copy, when an item is chosen for
    /// pasting without that access. Modal.
    public func askToPasteToOtherApps() -> PasteToOtherAppsResult {
        // What holds if the window goes away without an answer: nothing is copied or pasted.
        var result = PasteToOtherAppsResult.enableAccessibilityAccess
        weak var presented: PermissionWindowController?
        let view = PasteToOtherAppsView(applicationName: NSWorkspace.shared.menuBarOwningApplication?.localizedName) {
            result = $0
            presented?.close()
        }
        let controller = PermissionWindowController(
            window: ChromelessWindow.make(isClosable: false, animationBehavior: .alertPanel),
            title: PermissionStrings.pasteToOtherAppsTitle(
                NSWorkspace.shared.menuBarOwningApplication?.localizedName ?? PermissionStrings.currentApplication
            ),
            content: view
        )
        presented = controller
        controller.runModal()
        return result
    }

    /// Walks the user through granting Accessibility access. Modal; closing the window cancels.
    public func requestAccessibilityAccess() -> PermissionOutcome {
        runAccessRequest(for: .accessibility)
    }

    /// Walks the user through setting pasteboard access to "always allow". Modal.
    @discardableResult
    public func requestPasteboardAccess() -> PermissionOutcome {
        runAccessRequest(for: .pasteboard)
    }

    /// Shows the window that asks for screen recording access, or brings it forward if it is
    /// already open. Not modal; the user closes it, granted or not.
    ///
    /// Once Pasto has the access, the window instead runs the capture check that gets macOS's
    /// own confirmation over with, and goes away by itself once it has. With the access granted
    /// and confirmed there is nothing to show.
    ///
    /// - Parameters:
    ///   - origin: Where the user asks from; after System Settings reopens Pasto, they are taken
    ///     back there.
    ///   - onClose: Called once the window is gone, or at once when there was nothing to show.
    public func showScreenRecordingAccess(from origin: ScreenRecordingRequest.Origin, onClose: (() -> Void)? = nil) {
        if ScreenRecordingAccess.isGranted, ScreenCaptureCheck.lastConfirmation(in: config) != nil {
            onClose?()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if let screenRecordingWindow {
            screenRecordingWindow.bringToFront()
            return
        }
        let model = ScreenRecordingAccessModel(config: config, origin: origin)
        let controller = PermissionWindowController(
            window: ChromelessWindow.make(isClosable: true, animationBehavior: .documentWindow),
            title: PermissionStrings.screenRecordingTitle,
            content: ScreenRecordingAccessView(model: model).permissionWindowFrame()
        )
        screenRecordingWindow = controller
        // Once macOS has confirmed, the check mark stays for a moment and the window goes.
        let closingWhenConfirmed = Task { [weak controller] in
            for await confirmation in Observations({ model.confirmation }) where confirmation == .confirmed {
                try? await Task.sleep(for: PermissionMetrics.grantedConfirmationDuration)
                controller?.close()
                return
            }
        }
        controller.show { [weak self] in
            closingWhenConfirmed.cancel()
            self?.screenRecordingWindow = nil
            onClose?()
        }
    }

    private func runAccessRequest(for permission: AccessRequestModel.Permission) -> PermissionOutcome {
        var outcome = PermissionOutcome.cancel
        weak var presented: PermissionWindowController?
        let model = AccessRequestModel(permission: permission, configuration: .regular) {
            outcome = $0
            presented?.close()
        }
        let controller = PermissionWindowController(
            window: ChromelessWindow.make(isClosable: true, animationBehavior: .documentWindow),
            title: permission == .accessibility ? PermissionStrings.accessibilityTitle : PermissionStrings.pasteboardTitle,
            content: AccessRequestView(model: model).permissionWindowFrame()
        )
        presented = controller
        model.window = controller
        controller.runModal()
        // However the window went, nothing is left watching for the grant.
        model.stopObserving()
        return outcome
    }
}

extension View {
    /// The fixed content size of the windows that ask for one permission.
    fileprivate func permissionWindowFrame() -> some View {
        frame(width: PermissionMetrics.windowContentSize.width, height: PermissionMetrics.windowContentSize.height)
    }
}
