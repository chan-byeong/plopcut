// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PlopcutApp",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../PlopcutCore")],
    targets: [
        .executableTarget(
            name: "Plopcut",
            dependencies: [.product(name: "PlopcutCore", package: "PlopcutCore")]),
        .testTarget(name: "PlopcutTests", dependencies: ["Plopcut"]),
    ],
    swiftLanguageModes: [.v6]
)
