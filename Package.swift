// swift-tools-version: 5.9

import PackageDescription


let package = Package(
    name: "AurumBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "aurumbar", targets: ["AurumBar"]),
    ],
    targets: [
        .target(name: "AurumBarCore"),
        .target(
            name: "AurumBarRuntime",
            dependencies: ["AurumBarCore"]
        ),
        .executableTarget(
            name: "AurumBar",
            dependencies: ["AurumBarCore", "AurumBarRuntime"]
        ),
        .testTarget(
            name: "AurumBarCoreTests",
            dependencies: ["AurumBarCore"]
        ),
        .testTarget(
            name: "AurumBarRuntimeTests",
            dependencies: ["AurumBarCore", "AurumBarRuntime"]
        ),
    ]
)
