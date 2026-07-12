// swift-tools-version: 6.0
// Darkroom — Linux-testable engine target.
//
// The Xcode app target (project.yml) compiles Sources/App + Sources/Engine
// together; this manifest exposes ONLY the pure engine so the puzzle
// compiler, line solver, and game logic build and test on any platform.
import PackageDescription

let package = Package(
    name: "DarkroomEngine",
    platforms: [.tvOS(.v18), .macOS(.v14)],
    dependencies: [.package(path: "../couchkit")],
    targets: [
        .target(
            name: "DarkroomEngine",
            dependencies: [.product(name: "CouchKit", package: "couchkit")],
            path: "Sources/Engine"
        ),
        .testTarget(
            name: "DarkroomEngineTests",
            dependencies: ["DarkroomEngine"],
            path: "Tests/EngineTests"
        ),
    ]
)
