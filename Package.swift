// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchAgent",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchAgent",
            path: "Sources/NotchAgent"
        ),
        .testTarget(
            name: "NotchAgentTests",
            dependencies: ["NotchAgent"],
            path: "Tests/NotchAgentTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
