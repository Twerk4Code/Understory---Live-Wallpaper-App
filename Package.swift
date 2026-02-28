// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Understory",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Understory",
            path: "Sources/Understory",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
