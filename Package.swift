// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AvatodoCore",
    platforms: [.iOS("27.0"), .watchOS("27.0"), .macOS(.v14)],
    products: [.library(name: "AvatodoCore", targets: ["AvatodoCore"])],
    targets: [
        .target(name: "AvatodoCore"),
        .testTarget(name: "AvatodoCoreTests", dependencies: ["AvatodoCore"])
    ]
)
