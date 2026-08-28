// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ToolBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ToolBarCore",
            path: "Sources/ToolBarCore"
        ),
        .executableTarget(
            name: "ToolBar",
            dependencies: ["ToolBarCore"],
            path: "Sources/ToolBar"
        ),
        .testTarget(
            name: "ToolBarTests",
            dependencies: ["ToolBarCore"],
            path: "Tests/ToolBarTests"
        ),
    ]
)
