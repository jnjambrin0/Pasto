import CoreGraphics
import Foundation
import ScreenCaptureKit

/// What to capture: one window on its own, or the composited contents of a display.
public enum CaptureTarget: Sendable, Equatable {
    case window(id: UInt32)
    /// `rect` is in points relative to the display's top-left corner; nil captures the whole display.
    case display(id: CGDirectDisplayID, rect: Frame?)
}

/// Description of a screenshot written to disk.
public struct CaptureInfo: Codable, Sendable {
    public let path: String
    public let width: Int
    public let height: Int
    /// Pixels per point of the capture.
    public let scale: Double
    /// `screencapturekit` or `screencapture` (the command-line fallback).
    public let method: String
}

@MainActor
public enum ScreenCapture {
    /// Captures `target` at native resolution and writes it as an sRGB PNG.
    ///
    /// Windows fall back to `/usr/sbin/screencapture` when ScreenCaptureKit refuses them, and use it
    /// outright for `includeShadow`: ScreenCaptureKit can draw the shadow, but it shrinks the window
    /// to make room for it, so the result is no longer at native scale.
    public static func capture(_ target: CaptureTarget, includeShadow: Bool = false, to url: URL) async throws -> CaptureInfo {
        try Permissions.requireScreenCapture()
        if includeShadow, case .window(let id) = target {
            return try captureWithCommandLineTool(windowID: id, includeShadow: true, to: url)
        }
        let captured: (image: CGImage, scale: Double)
        do {
            captured = try await captureWithScreenCaptureKit(target)
        } catch {
            guard case .window(let id) = target else { throw describe(error) }
            return try captureWithCommandLineTool(windowID: id, includeShadow: false, to: url, after: error)
        }
        try PNGFile.write(captured.image, to: url)
        return CaptureInfo(
            path: url.path, width: captured.image.width, height: captured.image.height,
            scale: captured.scale, method: "screencapturekit"
        )
    }

    /// Captures `target` straight into memory, without the command-line fallback.
    public static func image(of target: CaptureTarget) async throws -> CGImage {
        try Permissions.requireScreenCapture()
        do {
            return try await captureWithScreenCaptureKit(target).image
        } catch {
            throw describe(error)
        }
    }

    private static func captureWithScreenCaptureKit(_ target: CaptureTarget) async throws -> (image: CGImage, scale: Double) {
        let (filter, configuration) = try await filterAndConfiguration(for: target)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return (image, Double(filter.pointPixelScale))
    }

    /// Builds the ScreenCaptureKit filter and a configuration sized to the target's native pixels.
    static func filterAndConfiguration(for target: CaptureTarget) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        switch target {
        case .window(let id):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw ProbeError.targetNotFound("window \(id) is not available to ScreenCaptureKit")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = Double(filter.pointPixelScale)
            configuration.ignoreShadowsSingleWindow = true
            configuration.width = Int((filter.contentRect.width * scale).rounded())
            configuration.height = Int((filter.contentRect.height * scale).rounded())
            return (filter, configuration)

        case .display(let id, let rect):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw ProbeError.targetNotFound("display \(id) is not available to ScreenCaptureKit")
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = Double(filter.pointPixelScale)
            let bounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
            let region = rect?.cgRect ?? bounds
            guard bounds.contains(region) else {
                throw ProbeError.usage(
                    "rectangle \(region.minX),\(region.minY),\(region.width),\(region.height) does not fit in the \(display.width)x\(display.height) display"
                )
            }
            configuration.sourceRect = region
            configuration.width = Int((region.width * scale).rounded())
            configuration.height = Int((region.height * scale).rounded())
            return (filter, configuration)
        }
    }

    private static func captureWithCommandLineTool(
        windowID: UInt32, includeShadow: Bool, to url: URL, after captureKitError: Error? = nil
    ) throws -> CaptureInfo {
        guard let window = WindowList.window(id: windowID) else {
            throw ProbeError.targetNotFound("no window with id \(windowID)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x"] + (includeShadow ? [] : ["-o"]) + ["-l", String(windowID), url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ProbeError.runtime("cannot run screencapture: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let size = PNGFile.pixelSize(of: url) else {
            let cause = captureKitError.map { "ScreenCaptureKit failed (\(describe($0).message)) and " } ?? ""
            throw ProbeError.runtime("\(cause)screencapture could not capture window \(windowID)")
        }
        return CaptureInfo(
            path: url.path, width: size.width, height: size.height,
            scale: Displays.scale(at: CGPoint(x: window.bounds.cgRect.midX, y: window.bounds.cgRect.midY)),
            method: "screencapture"
        )
    }

    private static func describe(_ error: Error) -> ProbeError {
        (error as? ProbeError) ?? .runtime("ScreenCaptureKit: \(error.localizedDescription)")
    }
}
