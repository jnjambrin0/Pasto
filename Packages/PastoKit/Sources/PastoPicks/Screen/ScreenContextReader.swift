import AppKit
import os
import PastoFoundation
import PastoPermissions
import ScreenCaptureKit

/// Looks at the window the user is about to paste into and asks the language model what kind
/// of field it shows.
///
/// One window of the destination application is captured, without the cursor, and the image
/// lives only in memory for the length of the question: it is never written, logged or scaled.
/// No text is read off the screen; the window's title only serves to tell real windows apart.
/// Any failure means "no answer": there is no retry.
actor ScreenContextReader {
    /// The step a failure happened in, for the log.
    private enum Step: String {
        case windows
        case capture
        case answer
    }

    private let client: any LanguageModelClient
    private let log = Log.logger(.picks)

    init(client: any LanguageModelClient) {
        self.client = client
    }

    /// The kind of field the frontmost window of the application with `bundleIdentifier` shows,
    /// or `nil` when it cannot be told.
    func fieldKind(ofApplication bundleIdentifier: String) async -> FieldKind? {
        guard ScreenRecordingAccess.isGranted, client.availability == .available,
              let processID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?.processIdentifier
        else { return nil }

        let lookup = await attempt(.windows) {
            try await withDeadline(PicksMetrics.windowLookupTimeout, expiry: LanguageModelClientError.timedOut) {
                try await Self.windowFilter(processID: processID).map(Handover.init)
            }
        }
        // No window to look at, or the lookup failed.
        guard let filter = lookup.flatMap(\.self)?.value else { return nil }

        guard let size = Self.pixelSize(of: filter.contentRect, scale: CGFloat(filter.pointPixelScale)) else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.shouldBeOpaque = true
        // Nothing about the window, not even its frame or size, goes to the log.

        let request = Handover((filter, configuration))
        let capture = await attempt(.capture) {
            try await withDeadline(PicksMetrics.captureTimeout, expiry: LanguageModelClientError.timedOut) {
                try await SCScreenshotManager.captureImage(contentFilter: request.value.0, configuration: request.value.1)
            }
        }
        guard let image = capture, !Task.isCancelled, client.acceptsImages else { return nil }
        let answer = await attempt(.answer) { [client] in try await client.fieldKind(in: image) }
        return answer.flatMap(\.self)
    }

    /// The first on-screen window of the process that has a title, in the order the system
    /// lists them. Desktop windows and off-screen ones are not listed.
    private static func windowFilter(processID: pid_t) async throws -> SCContentFilter? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let window = content.windows.first {
            isCandidate(processID: $0.owningApplication?.processID, isOnScreen: $0.isOnScreen, title: $0.title, of: processID)
        }
        return window.map { SCContentFilter(desktopIndependentWindow: $0) }
    }

    static func isCandidate(processID: pid_t?, isOnScreen: Bool, title: String?, of target: pid_t) -> Bool {
        processID == target && isOnScreen && !(title ?? "").isEmpty
    }

    /// The window's size in pixels, its longer side brought down to the capture limit; `nil`
    /// for a window less than a pixel wide or high.
    static func pixelSize(of contentRect: CGRect, scale: CGFloat) -> (width: Int, height: Int)? {
        var width = contentRect.width * scale
        var height = contentRect.height * scale
        let longerSide = max(width, height)
        if longerSide > PicksMetrics.maximumCaptureSide {
            let factor = PicksMetrics.maximumCaptureSide / longerSide
            width *= factor
            height *= factor
        }
        let size = (width: Int(width), height: Int(height))
        return size.width >= 1 && size.height >= 1 ? size : nil
    }

    /// Carries ScreenCaptureKit's filter and configuration into the task that races the deadline.
    /// They are created here, never changed once handed over, and only read by the system.
    private struct Handover<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    /// The result of `operation`, or `nil` if it failed; a failure other than cancellation is
    /// logged with its step.
    private func attempt<T>(_ step: Step, _ operation: () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch is CancellationError {
            return nil
        } catch {
            log.error("Could not read the destination's screen at \(step.rawValue, privacy: .public): \(error)")
            return nil
        }
    }
}
