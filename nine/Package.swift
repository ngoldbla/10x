// swift-tools-version: 6.0
// Nine — SwiftPM manifest for the pure engine, so the puzzle proof machinery
// builds and tests on Linux CI. The tvOS app target lives in project.yml.
import PackageDescription

let package = Package(
    name: "NineEngine",
    platforms: [.tvOS(.v18), .macOS(.v14)],
    dependencies: [.package(path: "../couchkit")],
    targets: [
        .target(
            name: "NineEngine",
            dependencies: [.product(name: "CouchKit", package: "couchkit")],
            path: "Sources/Engine"
        ),
        .testTarget(
            name: "NineEngineTests",
            dependencies: ["NineEngine"],
            path: "Tests/EngineTests"
        ),
        // The app↔widget bridge (PRD-3): pure Foundation, no CouchKit, so it
        // compiles into the widget extension untouched. Tested here against
        // the Engine originals it deliberately duplicates.
        .target(
            name: "NineShared",
            // SharedDailyBoard carries the Engine's NineGame; in the app and
            // widget targets the Engine compiles in directly, here it's a
            // module dependency.
            dependencies: ["NineEngine"],
            path: "Sources/Shared"
        ),
        .testTarget(
            name: "NineSharedTests",
            dependencies: ["NineShared", "NineEngine"],
            path: "Tests/SharedTests"
        ),
    ]
)
