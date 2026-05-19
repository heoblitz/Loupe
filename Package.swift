// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "loupe",
    platforms: [
        .iOS(.v15),
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
            name: "LoupeCLICore",
            dependencies: ["LoupeCore"]
        ),
        .executableTarget(
            name: "LoupeCLI",
            dependencies: ["LoupeCore", "LoupeHID", "LoupeCLICore"]
        ),
        .testTarget(
            name: "LoupeCoreTests",
            dependencies: ["LoupeCore"]
        ),
        .testTarget(
            name: "LoupeCLICoreTests",
            dependencies: ["LoupeCLICore"]
        ),
    ]
)
