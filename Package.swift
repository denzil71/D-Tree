// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DTree",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DTree",
            path: "Sources/DTree"
        )
    ]
)
