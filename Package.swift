// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftLauncher",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftLauncher", targets: ["SwiftLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "SwiftLauncher",
            path: "SwiftLauncher",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SwiftLauncherTests",
            dependencies: ["SwiftLauncher"],
            path: "SwiftLauncherTests"
        )
    ]
)
