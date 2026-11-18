import AppKit
@testable import PastoPermissions
import SwiftUI
import Testing

/// Not a test of the windows' look (there are no UI suites): a renderer that writes the permission
/// windows with their illustrations to PNG, in light and dark, to check that the 8:5 pictures fit
/// the 544 × 680 template and the 280 pt prompt. It does nothing unless PASTO_ILLUSTRATION_RENDERS
/// names an output folder:
///
///     PASTO_ILLUSTRATION_RENDERS=/tmp/renders swift test --package-path Packages/PastoKit --filter PermissionWindowRenders
@MainActor
struct PermissionWindowRenders {
    @Test func renderPermissionWindows() throws {
        guard let path = ProcessInfo.processInfo.environment["PASTO_ILLUSTRATION_RENDERS"], !path.isEmpty else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The template shows the app icon, which needs the application object.
        _ = NSApplication.shared

        let screens: [(String, String, String, PermissionIllustration.Kind)] = [
            ("window-accessibility", PermissionStrings.accessibilityTitle, PermissionStrings.accessibilitySubtitle, .accessibility),
            ("window-pasteboard", PermissionStrings.pasteboardTitle, PermissionStrings.pasteboardSubtitle, .pasteboard),
            ("window-suggestions", PermissionStrings.screenRecordingTitle, PermissionStrings.screenRecordingSubtitle, .suggestions),
        ]
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            for (name, title, subtitle, kind) in screens {
                // The windows have one button; "Not Now" belongs to the welcome's own steps.
                let window = PermissionTemplate(title: title, subtitle: subtitle, illustration: kind) {
                    PermissionButton(title: PermissionStrings.openSystemSettings, style: .filled) {}
                }
                try write(render(window, size: PermissionMetrics.windowContentSize, scheme: scheme),
                          to: folder.appendingPathComponent("\(name)-\(suffix).png"))
            }
            let prompt = PasteToOtherAppsView(applicationName: "TextEdit") { _ in }
            try write(render(prompt.fixedSize(), size: nil, scheme: scheme),
                      to: folder.appendingPathComponent("window-paste-to-other-apps-\(suffix).png"))
        }
    }

    private func render(_ view: some View, size: CGSize?, scheme: ColorScheme) throws -> CGImage {
        let background = scheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.17) : Color(red: 0.93, green: 0.93, blue: 0.93)
        let framed = Group {
            if let size {
                view.frame(width: size.width, height: size.height)
            } else {
                view
            }
        }
        .background(background)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
