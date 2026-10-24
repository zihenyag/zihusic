// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZihuMusic",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "zihusic", targets: ["ZihuMusic"])
    ],
    targets: [
        .executableTarget(
            name: "ZihuMusic",
            exclude: [
                "Icon/icon.original.png"
            ],
            resources: [
                .process("Icon/icon.png")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AVKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(name: "ZihuMusicTests", dependencies: ["ZihuMusic"])
    ]
)
