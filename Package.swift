// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StatusAppBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "StatusAppBar",
            path: "Sources/StatusAppBar"
        )
    ]
)
