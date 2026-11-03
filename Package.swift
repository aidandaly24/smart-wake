// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SmartWakeCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "SmartWakeCore", targets: ["SmartWakeCore"])],
    targets: [
        .target(name: "SmartWakeCore"),
        .testTarget(name: "SmartWakeCoreTests", dependencies: ["SmartWakeCore"])
    ]
)
