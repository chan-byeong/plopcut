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
        // In-app updates (PLO-118): checks the appcast on plopcut.com and installs signed releases, pinned exactly.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Plopcut",
            dependencies: [
                .product(name: "PlopcutCore", package: "PlopcutCore"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Highlighter", package: "HighlighterSwift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ]),
        .testTarget(name: "PlopcutTests", dependencies: ["Plopcut"]),
    ],
    swiftLanguageModes: [.v6]
)
