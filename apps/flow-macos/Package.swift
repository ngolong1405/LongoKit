// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoFlow",
    platforms: [.macOS(.v13)],
    products: [
        // Everything but `@main`, so the LongoKit app can host Longo Flow too.
        .library(name: "LongoFlowKit", targets: ["LongoFlowKit"]),
    ],
    dependencies: [
        .package(path: "../../packages/ui-macos")
    ],
    targets: [
        .target(
            name: "LongoFlowKit",
            dependencies: [.product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoFlowKit"
        ),
        .executableTarget(
            name: "LongoFlow",
            dependencies: ["LongoFlowKit", .product(name: "LongoKitUI", package: "ui-macos")],
            path: "Sources/LongoFlow"
        ),
        // Pairing and the encrypted link, two devices in one process: `swift test`.
        .testTarget(
            name: "LongoFlowTests",
            dependencies: ["LongoFlowKit"],
            path: "Tests"
        ),
    ]
)
