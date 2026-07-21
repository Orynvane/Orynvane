// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Orynvane",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "OrynvaneCore", targets: ["OrynvaneCore"]),
        .executable(name: "Orynvane", targets: ["Orynvane"])
    ],
    targets: [
        .target(
            name: "OrynvaneCore",
            path: "Sources/OrynvaneCore"
        ),
        .executableTarget(
            name: "Orynvane",
            dependencies: ["OrynvaneCore"],
            path: "Sources/OrynvaneApp",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit")
            ]
        ),
        .testTarget(
            name: "OrynvaneCoreTests",
            dependencies: ["OrynvaneCore"],
            path: "Tests/OrynvaneCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
