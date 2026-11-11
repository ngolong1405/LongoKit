// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoDisplay",
    platforms: [.macOS(.v13)],
    products: [
        // Everything but `@main`, so the LongoKit app can host Longo Display too.
        .library(name: "LongoDisplayKit", targets: ["LongoDisplayKit"]),
    ],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .target(
            name: "LongoDisplayKit",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoDisplayKit"
        ),
        .executableTarget(
            name: "LongoDisplay",
            dependencies: ["LongoDisplayKit", .product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoDisplay"
        ),
    ]
)
