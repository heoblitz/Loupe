// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "loupe",
    platforms: [
        .iOS(.v15),
        .tvOS(.v15),
        .macOS(.v14),
        .watchOS(.v8),
        .visionOS(.v1),
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
    ],
    targets: [
        .target(
            name: "LoupeCore"
        ),
        .target(
            name: "LoupeKit",
            dependencies: ["LoupeCore", "LoupeSyntheticEvents"]
        ),
        .target(
            name: "LoupeInjection",
            dependencies: ["LoupeKit"]
        ),
        .target(
            name: "LoupeInjectionBootstrap",
            publicHeadersPath: "include",
            cSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .target(
            name: "LoupeHID",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("IOSurface"),
                .linkedFramework("ImageIO"),
            ]
        ),
        .target(
            name: "LoupeSyntheticEvents",
            publicHeadersPath: "include",
            cSettings: [.define("DEBUG", .when(configuration: .debug))],
            linkerSettings: [
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("QuartzCore", .when(platforms: [.iOS])),
                .linkedFramework("IOKit", .when(platforms: [.iOS])),
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
