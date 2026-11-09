// swift-tools-version:5.9
import PackageDescription

// LongoKit's shared SwiftUI design system: colors, fonts, controls, and localization helpers.
let package = Package(
    name: "LongoKitUI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LongoKitUI", targets: ["LongoKitUI"])
    ],
    targets: [
        .target(name: "LongoKitUI", path: "Sources/LongoKitUI")
    ]
)
