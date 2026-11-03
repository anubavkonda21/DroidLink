// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DroidLink",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DroidLink",
            targets: ["DroidLink"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DroidLink",
            dependencies: [],
            path: ".",
            exclude: [
                "Package.swift"
            ],
            sources: [
                "App",
                "Views",
                "Services",
                "Models"
            ]
        )
    ]
)
