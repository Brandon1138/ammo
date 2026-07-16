// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ammo",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "UsageKit", targets: ["UsageKit"]),
        .executable(name: "ammo-harness", targets: ["AmmoHarness"]),
    ],
    targets: [
        .target(name: "UsageKit"),
        .executableTarget(name: "AmmoHarness", dependencies: ["UsageKit"]),
        .testTarget(name: "UsageKitTests", dependencies: ["UsageKit"]),
    ]
)
