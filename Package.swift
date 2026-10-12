// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlassComposer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "GlassComposer", targets: ["GlassComposer"])
    ],
    targets: [
        .target(name: "GlassComposer"),
        .testTarget(name: "GlassComposerTests", dependencies: ["GlassComposer"])
    ]
)
