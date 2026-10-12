// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaloryComposer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MaloryComposer", targets: ["MaloryComposer"])
    ],
    targets: [
        .target(name: "MaloryComposer"),
        .testTarget(name: "MaloryComposerTests", dependencies: ["MaloryComposer"])
    ]
)
