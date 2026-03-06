// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexToolbar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexToolbar", targets: ["CodexToolbar"])
    ],
    targets: [
        .executableTarget(
            name: "CodexToolbar",
            path: "Sources/CodexToolbar",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CodexToolbarTests",
            dependencies: ["CodexToolbar"],
            path: "Tests/CodexToolbarTests"
        )
    ]
)
