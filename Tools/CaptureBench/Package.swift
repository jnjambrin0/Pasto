// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Measures what heavy content costs Pasto: capturing and restoring large items, decoding card
// thumbnails, searching a large index and polling the pasteboard at rest. Build it in release:
//
//     swift run -c release capturebench --help
//
// It never touches the general pasteboard's contents, the app's store, its settings or its
// search index: every run works in a directory, a settings suite and a Spotlight index of its own.

/// An embedded Info.plist gives the executable a bundle identifier of its own, which Core
/// Spotlight needs to keep an index for it.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist")
    .path

let package = Package(
    name: "CaptureBench",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../../Packages/PastoKit"),
    ],
    targets: [
        .executableTarget(
            name: "capturebench",
            dependencies: [.product(name: "PastoApp", package: "PastoKit")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", infoPlist]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
