// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flipbook",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Flipbook", targets: ["Flipbook"]),
        .executable(name: "flipbook-demo", targets: ["flipbook-demo"]),
    ],
    targets: [
        .target(name: "Flipbook", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "flipbook-demo",
            dependencies: ["Flipbook"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "chord-promo",
            dependencies: ["Flipbook"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FlipbookTests",
            dependencies: ["Flipbook"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
