// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Macndroid",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Macndroid",
            path: "Sources/Macndroid"
        )
    ]
)
