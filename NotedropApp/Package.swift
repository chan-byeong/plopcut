// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotedropApp",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../NotedropCore")],
    targets: [
        .executableTarget(
            name: "Notedrop",
            dependencies: [.product(name: "NotedropCore", package: "NotedropCore")]),
        .testTarget(name: "NotedropTests", dependencies: ["Notedrop"]),
    ],
    swiftLanguageModes: [.v6]
)
