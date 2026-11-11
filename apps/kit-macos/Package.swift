// swift-tools-version:5.9
import PackageDescription

// LongoKit: Longo Mouse, Display, Keys and Shot in one menu bar app, each a module to turn on or off.
let package = Package(
    name: "LongoKit",
    // Longo Shot's screenshots (SCScreenshotManager) need macOS 14.
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../packages/ui-macos"),
        .package(path: "../mouse-macos"),
        .package(path: "../display-macos"),
        .package(path: "../keys-macos"),
        .package(path: "../shot-macos"),
    ],
    targets: [
        .executableTarget(
            name: "LongoKit",
            dependencies: [
                .product(name: "LongoKitUI", package: "ui-macos"),
                .product(name: "LongoMouseKit", package: "mouse-macos"),
                .product(name: "LongoDisplayKit", package: "display-macos"),
                .product(name: "LongoKeysKit", package: "keys-macos"),
                .product(name: "LongoShotKit", package: "shot-macos"),
            ],
            path: "Sources/LongoKit"
        )
    ]
)
