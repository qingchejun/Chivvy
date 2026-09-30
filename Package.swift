// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chivvy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Chivvy",
            path: "Sources/Chivvy",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
