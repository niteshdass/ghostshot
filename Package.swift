// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ghostshot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GhostshotCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "GhostshotApp",
            dependencies: ["GhostshotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GhostshotCoreTests",
            dependencies: ["GhostshotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
