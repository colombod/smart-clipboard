// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartClipboard",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SmartClipboard", targets: ["SmartClipboard"])],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .target(name: "ClipboardCore", dependencies: [.product(name: "Yams", package: "Yams")], resources: [.process("Resources")]),
        .executableTarget(name: "SmartClipboard", dependencies: ["ClipboardCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "SmartClipboardTests", dependencies: ["SmartClipboard", "ClipboardCore", .product(name: "Yams", package: "Yams")])
    ],
    swiftLanguageModes: [.v5]
)
