// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AvatodoCore",
    platforms: [.iOS("26.0"), .watchOS("26.0"), .macOS(.v14)],
    products: [
        .library(name: "AvatodoCore", targets: ["AvatodoCore"]),
        .executable(name: "AvatodoProbe", targets: ["AvatodoProbe"])
    ],
    targets: [
        .target(name: "AvatodoCore"),
        .executableTarget(name: "AvatodoProbe", dependencies: ["AvatodoCore"]),
        .testTarget(name: "AvatodoCoreTests", dependencies: ["AvatodoCore"])
    ]
)
