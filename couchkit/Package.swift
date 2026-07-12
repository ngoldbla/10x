// swift-tools-version: 6.0
// CouchKit — the shared foundation of the Couch Suite (tvOS).
//
// Two targets by design:
//   • CouchCore — pure Swift + Foundation. Every algorithm lives here so it
//     builds and tests anywhere (including Linux CI, which has no SwiftUI).
//   • CouchKit  — the SwiftUI/tvOS layer. Every file is wrapped in
//     `#if os(tvOS)` so the target compiles to nothing on other platforms
//     (macOS can import SwiftUI but lacks the tvOS-only remote APIs).
import PackageDescription

let package = Package(
    name: "CouchKit",
    platforms: [
        .tvOS(.v18)
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
