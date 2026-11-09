// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoMouse",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .executableTarget(
            name: "LongoMouse",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoMouse"
        )
    ]
)
