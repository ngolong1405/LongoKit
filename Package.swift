// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MouseMapper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MouseMapper", path: "Sources/MouseMapper")
    ]
)
