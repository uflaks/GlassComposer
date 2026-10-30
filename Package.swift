// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlassComposer",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "GlassComposer", targets: ["GlassComposer"])
    ],
    targets: [
        .target(name: "GlassComposer"),
        .testTarget(name: "GlassComposerTests", dependencies: ["GlassComposer"])
    ]
)
