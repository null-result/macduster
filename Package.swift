// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MacDuster",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "MacDusterCore"),
        .executableTarget(name: "MacDuster", dependencies: ["MacDusterCore"]),
        .testTarget(name: "MacDusterCoreTests", dependencies: ["MacDusterCore"]),
    ]
)
