// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartClipboard",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SmartClipboard", targets: ["SmartClipboard"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [
        .target(name: "ClipboardCore", dependencies: [.product(name: "Yams", package: "Yams")]),
        .executableTarget(name: "SmartClipboard", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "SmartClipboardTests", dependencies: ["SmartClipboard", "ClipboardCore"])
    ],
    swiftLanguageModes: [.v5]
)
