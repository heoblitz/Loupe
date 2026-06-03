// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "loupe",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "LoupeCore",
            targets: ["LoupeCore"]
        ),
        .library(
            name: "LoupeKit",
            targets: ["LoupeKit"]
        ),
        .library(
            name: "LoupeInjector",
            type: .dynamic,
            targets: ["LoupeInjection", "LoupeInjectionBootstrap"]
        ),
        .executable(
            name: "loupe",
            targets: ["LoupeCLI"]
        ),
        .executable(
            name: "MacLoupeExample",
            targets: ["MacLoupeExample"]
        ),
    ],
    targets: [
        .target(
            name: "LoupeCore"
        ),
        .target(
            name: "LoupeKit",
            dependencies: ["LoupeCore"]
        ),
        .target(
            name: "LoupeInjection",
            dependencies: ["LoupeKit"]
        ),
        .target(
            name: "LoupeInjectionBootstrap",
            publicHeadersPath: "include"
        ),
        .target(
            name: "LoupeHID",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "LoupeCLIModel",
            dependencies: ["LoupeCore"]
        ),
        .executableTarget(
            name: "LoupeCLI",
            dependencies: ["LoupeCore", "LoupeHID", "LoupeCLIModel"]
        ),
        .executableTarget(
            name: "MacLoupeExample",
            dependencies: ["LoupeCore", "LoupeKit"],
            path: "Examples/MacLoupeExample",
            exclude: ["run-macos-e2e.sh"]
        ),
        .testTarget(
            name: "LoupeCoreTests",
            dependencies: ["LoupeCore"]
        ),
        .testTarget(
            name: "LoupeCLIModelTests",
            dependencies: ["LoupeCLIModel"]
        ),
        .testTarget(
            name: "LoupeCLITests",
            dependencies: ["LoupeCLI"]
        ),
        .testTarget(
            name: "LoupeKitPlatformTests",
            dependencies: ["LoupeCore", "LoupeKit"]
        ),
    ]
)
