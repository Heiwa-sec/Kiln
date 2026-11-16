// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KilnCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "KilnCore", targets: ["KilnCore"])],
    targets: [
        .target(name: "KilnCore"),
        .testTarget(name: "KilnCoreTests", dependencies: ["KilnCore"]),
    ]
)
