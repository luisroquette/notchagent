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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
    ],
    targets: [
        .target(
            name: "AgentMeterCore",
            path: "Sources/AgentMeterCore"
        ),
        .executableTarget(
            name: "NotchAgent",
            dependencies: [
                "AgentMeterCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/NotchAgent",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
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
