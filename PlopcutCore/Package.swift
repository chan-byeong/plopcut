// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PlopcutCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PlopcutCore", targets: ["PlopcutCore"])],
    targets: [
        .target(name: "PlopcutCore"),
        .testTarget(name: "PlopcutCoreTests", dependencies: ["PlopcutCore"]),
    ],
    swiftLanguageModes: [.v6]
)
