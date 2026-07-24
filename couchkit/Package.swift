// swift-tools-version: 6.0
// CouchKit — the shared foundation of the Couch Suite (tvOS).
//
// Two targets by design:
//   • CouchCore — pure Swift + Foundation. Every algorithm lives here so it
//     builds and tests anywhere (including Linux CI, which has no SwiftUI).
//   • CouchKit  — the SwiftUI layer. Glass, typography, persistence and help
//     components compile for tvOS, iOS *and* macOS (Nine ships universal —
//     PRD-4 adds the Mac as the third destination); the remote-input layer
//     (RemoteKit) and TV-only kits stay `#if os(tvOS)`. Every file carries a
//     platform guard so the target compiles to nothing on platforms that
//     lack the APIs it wraps.
import PackageDescription

let package = Package(
    name: "CouchKit",
    platforms: [
        .tvOS(.v18),
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "CouchKit", targets: ["CouchKit", "CouchCore"])
    ],
    targets: [
        .target(name: "CouchCore"),
        .target(name: "CouchKit", dependencies: ["CouchCore"]),
        .testTarget(name: "CouchCoreTests", dependencies: ["CouchCore"]),
        // Exercises the pure PadKit grammar (momentum curve, stick classifier,
        // button sampler) on the Mac — closes the CI gap that let the broken
        // tvOS controller mapping ship: `swift test` used to compile PadKit out
        // entirely because the whole file was `#if os(tvOS)` (PRD-5 Phase 4.1).
        .testTarget(name: "CouchKitTests", dependencies: ["CouchKit"]),
    ]
)
