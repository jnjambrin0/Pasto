// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ProbeKit",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "ProbeCore", targets: ["ProbeCore"]),
        .executable(name: "pastoprobe", targets: ["pastoprobe"]),
        .executable(name: "ProbeTarget", targets: ["ProbeTarget"]),
    ],
    targets: [
        .target(name: "ProbeCore"),
        .executableTarget(name: "pastoprobe", dependencies: ["ProbeCore"]),
        .executableTarget(name: "ProbeTarget", dependencies: ["ProbeCore"]),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
    ],
    swiftLanguageModes: [.v6]
)
