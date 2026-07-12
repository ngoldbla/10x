// swift-tools-version: 6.0
// Cartridge — Linux-testable slice. Only the pure engine builds here;
// the SwiftUI app target is produced by project.yml (XcodeGen) on a Mac.
import PackageDescription

let package = Package(
    name: "CartridgeEngine",
    platforms: [.tvOS(.v18), .macOS(.v14)],
    dependencies: [.package(path: "../couchkit")],
    targets: [
        .target(
            name: "CartridgeEngine",
            dependencies: [.product(name: "CouchKit", package: "couchkit")],
            path: "Sources/Engine"
        ),
        .testTarget(
            name: "CartridgeEngineTests",
            dependencies: ["CartridgeEngine"],
            path: "Tests/EngineTests"
        ),
    ]
)
