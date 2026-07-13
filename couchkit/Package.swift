// swift-tools-version: 6.0
// CouchKit — the shared foundation of the Couch Suite (tvOS).
//
// Two targets by design:
//   • CouchCore — pure Swift + Foundation. Every algorithm lives here so it
//     builds and tests anywhere (including Linux CI, which has no SwiftUI).
//   • CouchKit  — the SwiftUI layer. Glass, typography, persistence and help
//     components compile for tvOS *and* iOS (Nine ships universal); the
//     remote-input layer (RemoteKit) and TV-only kits stay `#if os(tvOS)`.
//     Every file carries a platform guard so the target compiles to nothing
//     elsewhere (macOS can import SwiftUI but lacks these platform APIs).
import PackageDescription

let package = Package(
    name: "CouchKit",
    platforms: [
        .tvOS(.v18),
        .iOS(.v18)
    ],
    products: [
        .library(name: "CouchKit", targets: ["CouchKit", "CouchCore"])
    ],
    targets: [
        .target(name: "CouchCore"),
        .target(name: "CouchKit", dependencies: ["CouchCore"]),
        .testTarget(name: "CouchCoreTests", dependencies: ["CouchCore"]),
    ]
)
