// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoShare",
    platforms: [.macOS(.v13)],
    products: [
        // Everything but `@main`, so the LongoKit app can host Longo Share too.
        .library(name: "LongoShareKit", targets: ["LongoShareKit"]),
    ],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .target(
            name: "LongoShareKit",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoShareKit"
        ),
        .executableTarget(
            name: "LongoShare",
            dependencies: ["LongoShareKit", .product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoShare"
        ),
        // The engine against itself over real sockets: `swift test`.
        .testTarget(
            name: "LongoShareTests",
            dependencies: ["LongoShareKit"],
            path: "Tests"
        ),
    ]
)
