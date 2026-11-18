// swift-tools-version: 6.2
import PackageDescription

// Writes Pasto's visual identity: the app icon set and the web exports from the painted artwork in
// Design/icon/source, the menu bar glyph, and the DMG window background and layout. Run it with
// `swift run --package-path Tools/IconKit iconkit --help`.

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
