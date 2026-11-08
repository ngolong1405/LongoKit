// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LongoMouse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LongoMouse", path: "Sources/LongoMouse")
    ]
)
