// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppIconFinder",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AppIconFinder",
            path: "Sources/AppIconFinder"
        )
    ]
)
