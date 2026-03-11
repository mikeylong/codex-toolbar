// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexToolbar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ToolbarCore", targets: ["ToolbarCore"]),
        .executable(name: "CodexToolbar", targets: ["CodexToolbar"]),
        .executable(name: "QuotaBar", targets: ["QuotaBar"])
    ],
    targets: [
        .target(
            name: "ToolbarCore",
            path: "Sources/CodexToolbar",
            exclude: [
                "Networking",
                "Resources"
            ]
        ),
        .executableTarget(
            name: "CodexToolbar",
            dependencies: ["ToolbarCore"],
            path: "Sources/CodexToolbarApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["ToolbarCore"],
            path: "Sources/QuotaBar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CodexToolbarTests",
            dependencies: ["ToolbarCore", "CodexToolbar", "QuotaBar"],
            path: "Tests/CodexToolbarTests"
        )
    ]
)
