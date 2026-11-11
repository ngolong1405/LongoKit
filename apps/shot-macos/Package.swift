// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoShot",
    // ScreenCaptureKit's screenshot API (SCScreenshotManager) needs macOS 14.
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .executableTarget(
            name: "LongoShot",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoShot"
        )
    ]
)
