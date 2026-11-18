// swift-tools-version: 6.2
import PackageDescription

// Renders Pasto's item cards to PNG files without showing a window, to review them at every
// density and appearance and to catch visual regressions. Run `swift run CardGallery --help`.

let package = Package(
    name: "CardGallery",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../../Packages/PastoKit"),
    ],
    targets: [
        .executableTarget(
            name: "CardGallery",
            dependencies: [.product(name: "PastoApp", package: "PastoKit")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
