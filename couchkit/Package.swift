// swift-tools-version: 6.0
// CouchKit — the shared foundation of the Couch Suite (tvOS).
//
// Two targets by design:
//   • CouchCore — pure Swift + Foundation. Every algorithm lives here so it
//     builds and tests anywhere (including Linux CI, which has no SwiftUI).
//   • CouchKit  — the SwiftUI layer. Glass, typography and persistence compile
//     for tvOS, iOS, macOS *and* watchOS (Nine ships universal — PRD-4 adds
//     the Mac, PRD-6 the wrist); the remote-input layer (RemoteKit) and TV-only
//     kits stay `#if os(tvOS)`, and HelpKit stays off the wrist because a
//     control legend is a thing you read on a couch. Every file carries a
//     platform guard so the target compiles to nothing on platforms that
//     lack the APIs it wraps.
import PackageDescription

let package = Package(
    name: "CouchKit",
    platforms: [
        .tvOS(.v18),
        .iOS(.v18),
        .macOS(.v15),
        // Adding a platform only introduces a floor for that platform; it
        // cannot move tvOS/iOS/macOS. Proved rather than assumed — a sibling
        // tvOS app is built in the same commit (PRD-6 Task 1 Step 5).
        .watchOS(.v11)
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
