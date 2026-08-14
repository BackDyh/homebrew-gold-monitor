// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AurumBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "aurumbar", targets: ["AurumBar"]),
        .executable(name: "aurumbar-checks", targets: ["AurumBarChecks"]),
    ],
    targets: [
        .target(name: "AurumBarCore"),
        .executableTarget(
            name: "AurumBar",
            dependencies: ["AurumBarCore"]
        ),
        .executableTarget(
            name: "AurumBarChecks",
            dependencies: ["AurumBarCore"]
        ),
    ]
)
