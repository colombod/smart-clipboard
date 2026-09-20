// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartClipboard",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SmartClipboard", targets: ["SmartClipboard"])],
    targets: [
        .target(name: "ClipboardCore"),
        .executableTarget(name: "SmartClipboard", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "SmartClipboardTests", dependencies: ["SmartClipboard", "ClipboardCore"])
    ],
    swiftLanguageModes: [.v5]
)
