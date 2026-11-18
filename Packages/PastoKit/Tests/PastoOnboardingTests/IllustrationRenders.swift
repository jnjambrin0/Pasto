import AppKit
@testable import PastoOnboarding
import PastoPermissions
import SwiftUI
import Testing

/// Not a test of the illustrations' look (there are no UI suites): a renderer that writes every
/// onboarding illustration to PNG, in light and dark, as imported picture and as vector fallback, to
/// look at them. It does nothing unless PASTO_ILLUSTRATION_RENDERS names an output folder:
///
///     PASTO_ILLUSTRATION_RENDERS=docs/design/img/onboarding swift test --package-path Packages/PastoKit \
///         --filter IllustrationRenders
@MainActor
struct IllustrationRenders {
    @Test func renderEveryIllustration() throws {
        guard let folder = renderFolder() else { return }
        for kind in OnboardingIllustration.Kind.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for artwork in [IllustrationArtwork.automatic, .vector] {
                    let name = "\(kind.rawValue)-\(artwork == .vector ? "vector" : "picture")-\(scheme == .dark ? "dark" : "light")"
                    let start = ContinuousClock.now
                    let image = try render(
                        OnboardingIllustration(kind)
                            .frame(width: 400, height: 250)
                            .padding(20)
                            .background(windowBackground(scheme))
                            .environment(\.colorScheme, scheme)
                            .environment(\.illustrationArtwork, artwork),
                        size: CGSize(width: 440, height: 290))
                    print("rendered \(name) in \(ContinuousClock.now - start)")
                    try write(image, to: folder.appendingPathComponent("\(name).png"))
                }
            }
        }
        // Contact sheets: one row per illustration, light and dark side by side.
        for artwork in [IllustrationArtwork.automatic, .vector] {
            let sheet = VStack(spacing: 0) {
                ForEach(OnboardingIllustration.Kind.allCases, id: \.self) { kind in
                    HStack(spacing: 0) {
                        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                            OnboardingIllustration(kind)
                                .frame(width: 400, height: 250)
                                .padding(20)
                                .background(windowBackground(scheme))
                                .environment(\.colorScheme, scheme)
                        }
                    }
                }
            }
            .environment(\.illustrationArtwork, artwork)
            let image = try render(sheet, size: CGSize(width: 880, height: 290 * CGFloat(OnboardingIllustration.Kind.allCases.count)))
            try write(image, to: folder.appendingPathComponent(artwork == .vector ? "sheet-vector.png" : "sheet-pictures.png"))
        }
    }

    private func renderFolder() -> URL? {
        guard let path = ProcessInfo.processInfo.environment["PASTO_ILLUSTRATION_RENDERS"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The window background of each appearance, approximately.
    private func windowBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.17) : Color(red: 0.93, green: 0.93, blue: 0.93)
    }

    private func render(_ view: some View, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
