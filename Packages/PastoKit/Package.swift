// swift-tools-version: 6.2
import PackageDescription

// Pasto's module graph. Layers only depend downwards and feature libraries (L3) never import
// each other. See docs/ARCHITECTURE.md before adding a target or a dependency edge.

let commonSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// UI modules run on the main actor by default; everything else is nonisolated by default.
let uiSettings: [SwiftSetting] = commonSettings + [.defaultIsolation(MainActor.self)]

func module(
    _ name: String,
    ui: Bool = false,
    dependsOn dependencies: [String] = [],
    resources: [Resource]? = nil
) -> Target {
    .target(
        name: name,
        dependencies: dependencies.map { .target(name: $0) },
        resources: resources,
        swiftSettings: ui ? uiSettings : commonSettings
    )
}

let package = Package(
    name: "PastoKit",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "PastoApp", targets: ["PastoApp"]),
    ],
    dependencies: [
        // In-app updates for builds distributed outside the App Store.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        // L0 — foundation
        module("PastoFoundation"),

        // L1 — domain, system services, design system
        module("PastoCore", dependsOn: ["PastoFoundation"]),
        module("PastoInput", dependsOn: ["PastoFoundation"]),
        // The permission windows use the design system's button style, hence the edge to PastoUI.
        module("PastoPermissions", dependsOn: ["PastoUI", "PastoFoundation"], resources: [.process("Resources")]),
        .testTarget(name: "PastoPermissionsTests", dependencies: ["PastoPermissions"], swiftSettings: commonSettings),
        module("PastoRecognition", dependsOn: ["PastoFoundation"]),
        module("PastoUI", ui: true, dependsOn: ["PastoFoundation"]),
        .testTarget(name: "PastoUITests", dependencies: ["PastoUI", "PastoFoundation"], swiftSettings: uiSettings),

        // L2 — services and shared UI built on Core
        module("PastoSearch", dependsOn: ["PastoCore", "PastoRecognition", "PastoFoundation"]),
        module("PastoPicks", dependsOn: ["PastoCore", "PastoPermissions", "PastoFoundation"]),
        .testTarget(name: "PastoPicksTests",
                    dependencies: ["PastoPicks", "PastoCore", "PastoFoundation"],
                    swiftSettings: commonSettings),
        .target(
            name: "PastoCoreUI",
            dependencies: ["PastoCore", "PastoUI", "PastoFoundation"],
            resources: [.process("Resources")],
            swiftSettings: uiSettings
        ),
        .testTarget(name: "PastoCoreUITests", dependencies: ["PastoCoreUI", "PastoCore", "PastoUI"], swiftSettings: uiSettings),

        // L3 — features
        module("PastoMainPanel", ui: true,
               dependsOn: ["PastoSearch", "PastoPicks", "PastoCoreUI", "PastoUI", "PastoCore", "PastoInput", "PastoFoundation"],
               resources: [.process("Resources")]),
        .testTarget(name: "PastoMainPanelTests", dependencies: ["PastoMainPanel"], swiftSettings: uiSettings),
        module("PastoPreview", ui: true,
               dependsOn: ["PastoCoreUI", "PastoUI", "PastoCore", "PastoRecognition", "PastoFoundation"],
               resources: [.process("Resources")]),
        .testTarget(name: "PastoPreviewTests",
                    dependencies: ["PastoPreview", "PastoCoreUI", "PastoCore"],
                    swiftSettings: uiSettings),
        module("PastoStack", ui: true,
               dependsOn: ["PastoCoreUI", "PastoUI", "PastoCore", "PastoInput", "PastoFoundation"],
               resources: [.process("Resources")]),
        .testTarget(name: "PastoStackTests", dependencies: ["PastoStack"], swiftSettings: uiSettings),
        module("PastoSettings", ui: true,
               dependsOn: ["PastoUI", "PastoCore", "PastoInput", "PastoPermissions", "PastoFoundation"],
               resources: [.process("Resources")]),
        .testTarget(name: "PastoSettingsTests",
                    dependencies: ["PastoSettings", "PastoInput", "PastoCore", "PastoFoundation"],
                    swiftSettings: uiSettings),
        module("PastoOnboarding", ui: true,
               dependsOn: ["PastoUI", "PastoCore", "PastoInput", "PastoPermissions", "PastoFoundation"],
               resources: [.process("Resources")]),
        .testTarget(name: "PastoOnboardingTests",
                    dependencies: ["PastoOnboarding", "PastoUI", "PastoFoundation"],
                    swiftSettings: uiSettings),
        module("PastoStatusItem", ui: true, dependsOn: ["PastoUI", "PastoCore", "PastoFoundation"]),
        .target(
            name: "PastoUpdates",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "PastoFoundation"],
            swiftSettings: uiSettings
        ),
        .testTarget(name: "PastoUpdatesTests", dependencies: ["PastoUpdates"], swiftSettings: uiSettings),

        // L4 — composition root
        module("PastoApp", ui: true, dependsOn: [
            "PastoMainPanel", "PastoPreview", "PastoStack", "PastoSettings", "PastoOnboarding",
            "PastoStatusItem", "PastoUpdates", "PastoCoreUI", "PastoUI", "PastoSearch", "PastoPicks",
            "PastoCore", "PastoInput", "PastoPermissions", "PastoRecognition", "PastoFoundation",
        ], resources: [.process("Resources")]),

        // Tests — pure logic and in-memory stores only (docs/DEVELOPMENT.md)
        .testTarget(name: "PastoFoundationTests", dependencies: ["PastoFoundation"], swiftSettings: commonSettings),
        .testTarget(name: "PastoCoreTests", dependencies: ["PastoCore", "PastoFoundation"], swiftSettings: commonSettings),
        .testTarget(name: "PastoSearchTests",
                    dependencies: ["PastoSearch", "PastoRecognition", "PastoCore", "PastoFoundation"],
                    swiftSettings: commonSettings),
    ],
    swiftLanguageModes: [.v6]
)
