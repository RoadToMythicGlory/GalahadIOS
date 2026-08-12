// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GalahadIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MediaCore", targets: ["MediaCore"]),
        .executable(name: "galahad-ts-dump", targets: ["TsDump"]),
    ],
    targets: [
        .target(
            name: "MediaCore",
            path: "MediaCore/Sources/MediaCore"
        ),
        .executableTarget(
            name: "TsDump",
            dependencies: ["MediaCore"],
            path: "Tools/TsDump"
        ),
        .testTarget(
            name: "MediaCoreTests",
            dependencies: ["MediaCore"],
            path: "MediaCore/Tests/MediaCoreTests"
        ),
    ]
)
