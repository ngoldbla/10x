// swift-tools-version: 6.0
// Blockhead — engine package. The pure-Swift game engine (question pack,
// linter, episode/party engines) lives in Sources/Engine and builds anywhere,
// including Linux CI. The SwiftUI app in Sources/App is built only by the
// XcodeGen project (project.yml).
import PackageDescription

let package = Package(
    name: "BlockheadEngine",
    platforms: [.tvOS(.v18), .macOS(.v14)],
    dependencies: [.package(path: "../couchkit")],
    targets: [
        .target(
            name: "BlockheadEngine",
            dependencies: [.product(name: "CouchKit", package: "couchkit")],
            path: "Sources/Engine"
        ),
        .testTarget(
            name: "BlockheadEngineTests",
            dependencies: [
                "BlockheadEngine",
                .product(name: "CouchKit", package: "couchkit"),
            ],
            path: "Tests/EngineTests"
        ),
    ]
)
