// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoKeys",
    platforms: [.macOS(.v13)],
    products: [
        // Everything but `@main`, so the LongoKit app can host Longo Keys too.
        .library(name: "LongoKeysKit", targets: ["LongoKeysKit"]),
    ],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .target(
            name: "LongoKeysKit",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoKeysKit"
        ),
        .executableTarget(
            name: "LongoKeys",
            dependencies: ["LongoKeysKit", .product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoKeys"
        ),
    ]
)
