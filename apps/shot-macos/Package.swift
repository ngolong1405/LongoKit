// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoShot",
    // ScreenCaptureKit's screenshot API (SCScreenshotManager) needs macOS 14.
    platforms: [.macOS(.v14)],
    products: [
        // Everything but `@main`, so the LongoKit app can host Longo Shot too.
        .library(name: "LongoShotKit", targets: ["LongoShotKit"]),
    ],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .target(
            name: "LongoShotKit",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoShotKit"
        ),
        .executableTarget(
            name: "LongoShot",
            dependencies: ["LongoShotKit", .product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoShot"
        ),
    ]
)
