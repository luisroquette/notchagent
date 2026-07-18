// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchAgent",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "AgentMeterCore", targets: ["AgentMeterCore"]),
    ],
    targets: [
        .target(
            name: "AgentMeterCore",
            path: "Sources/AgentMeterCore"
        ),
        .executableTarget(
            name: "NotchAgent",
            dependencies: ["AgentMeterCore"],
            path: "Sources/NotchAgent"
        ),
        .testTarget(
            name: "AgentMeterCoreTests",
            dependencies: ["AgentMeterCore"],
            path: "Tests/AgentMeterCoreTests"
        ),
        .testTarget(
            name: "NotchAgentTests",
            dependencies: ["NotchAgent"],
            path: "Tests/NotchAgentTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
