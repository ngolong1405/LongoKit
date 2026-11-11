// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoMouse",
    platforms: [.macOS(.v13)],
    products: [
        // Everything but `@main`, so the LongoKit app can host Longo Mouse too.
        .library(name: "LongoMouseKit", targets: ["LongoMouseKit"]),
    ],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .target(
            name: "LongoMouseKit",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoMouseKit"
        ),
        .executableTarget(
            name: "LongoMouse",
            dependencies: ["LongoMouseKit", .product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoMouse"
        ),
    ]
)
