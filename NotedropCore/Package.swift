// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotedropCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NotedropCore", targets: ["NotedropCore"])],
    targets: [
        .target(name: "NotedropCore"),
        .testTarget(name: "NotedropCoreTests", dependencies: ["NotedropCore"]),
    ],
    swiftLanguageModes: [.v6]
)
