// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppIconSetter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AppIconSetter",
            path: "Sources/AppIconSetter"
        )
    ]
)
