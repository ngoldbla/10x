// swift-tools-version: 6.0
// Rabbit Ears — Linux-testable engine package. The tvOS app target (see
// project.yml) compiles Sources/App + Sources/Engine directly; this manifest
// exists so `swift build && swift test` can verify the engine anywhere.
import PackageDescription

let package = Package(
    name: "RabbitEarsEngine",
    platforms: [.tvOS(.v18), .macOS(.v14)],
    dependencies: [.package(path: "../couchkit")],
    targets: [
        .target(
            name: "RabbitEarsEngine",
            dependencies: [.product(name: "CouchKit", package: "couchkit")],
            path: "Sources/Engine"
        ),
        .testTarget(
            name: "RabbitEarsEngineTests",
            dependencies: ["RabbitEarsEngine"],
            path: "Tests/EngineTests"
        ),
    ]
)
