// swift-tools-version: 6.2
import PackageDescription

// Stress bench for Pasto's store and item list at a year of heavy use.
// Build and run it optimised: `swift run -c release pastostress help`.

let package = Package(
    name: "StressKit",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "pastostress", targets: ["pastostress"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PastoKit"),
    ],
    targets: [
        .executableTarget(
            name: "pastostress",
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
