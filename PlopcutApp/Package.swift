// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PlopcutApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../PlopcutCore"),
        // Body rendering (PLO-101): Markdown parsing and offline syntax highlighting, pinned exactly.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        .package(url: "https://github.com/smittytone/HighlighterSwift.git", exact: "3.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Plopcut",
            dependencies: [
                .product(name: "PlopcutCore", package: "PlopcutCore"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlighter", package: "HighlighterSwift"),
            ]),
        .testTarget(name: "PlopcutTests", dependencies: ["Plopcut"]),
    ],
    swiftLanguageModes: [.v6]
)
