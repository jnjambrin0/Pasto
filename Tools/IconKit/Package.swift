// swift-tools-version: 6.2
import PackageDescription

// Draws every piece of Pasto's visual identity from one vector description: the app icon (asset
// catalog and Icon Composer document), the menu-bar glyph, the DMG window background and the
// exports for the web. Run it with `swift run --package-path Tools/IconKit iconkit --help`.

let package = Package(
    name: "IconKit",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "iconkit",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
