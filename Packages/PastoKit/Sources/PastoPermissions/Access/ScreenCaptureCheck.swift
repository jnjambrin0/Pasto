import AppKit
import os
import PastoFoundation
import ScreenCaptureKit

/// A screen capture made on purpose, right after the user has been told what macOS will ask.
///
/// macOS 15 and later confirm, with an alert of their own ("… is requesting to bypass the system
/// private window picker and directly access your screen and audio"), that an app with screen
/// recording access may capture without the system picker. It comes up the first time the app
/// captures after the grant and again about once a month (Apple: macOS 15.1 release notes;
/// Apple staff on the developer forums, thread 765103). Suggestions capture when the panel
/// opens, and the alert would close the panel; this check makes the same calls — list the
/// windows on screen, capture one window of another app — so the alert comes while the user
/// expects it. The image is a few pixels wide and is thrown away at once.
public enum ScreenCaptureCheck {
    public enum Outcome: Equatable, Sendable {
        /// The capture went through: macOS has nothing left to ask for now.
        case confirmed
        /// Pasto has no screen recording access in this process.
        case notGranted
        /// macOS refused the capture, or the user did not allow it.
        case failed
    }

    /// The side, in pixels, of the throwaway capture.
    static let captureSide = 16

    /// Runs the check and remembers when it went through. Waits for as long as the user takes to
    /// answer macOS.
    @MainActor
    public static func run(config: ConfigStore) async -> Outcome {
        guard ScreenRecordingAccess.isGranted else { return .notGranted }
        let log = Log.logger(.app)
        do {
            try await captureAWindow()
            config.set(Date().timeIntervalSinceReferenceDate, for: .screenCaptureConfirmationTime)
            log.notice("Screen capture check went through")
            return .confirmed
        } catch {
            log.error("Screen capture check failed: \(error)")
            return .failed
        }
    }

    /// When the check last went through, if it ever did.
    public static func lastConfirmation(in config: ConfigStore) -> Date? {
        let time = config.value(for: .screenCaptureConfirmationTime)
        return time > 0 ? Date(timeIntervalSinceReferenceDate: time) : nil
    }

    @concurrent
    private static func captureAWindow() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        let others = content.windows.filter { $0.owningApplication?.processID != ownProcess && $0.isOnScreen }
        let window = others.first { !($0.title ?? "").isEmpty } ?? others.first
        let filter: SCContentFilter
        if let window {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else if let display = content.displays.first {
            filter = SCContentFilter(display: display, excludingWindows: [])
        } else {
            return
        }
        let configuration = SCStreamConfiguration()
        configuration.width = captureSide
        configuration.height = captureSide
        configuration.showsCursor = false
        _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
