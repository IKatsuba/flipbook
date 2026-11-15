// swift-tools-version: 6.0
import PackageDescription

// Flipbook's own promo, made with Flipbook. A separate package, so the library carries no scenes.
let package = Package(
    name: "promo",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "Flipbook", path: "../..")],
    targets: [
        .executableTarget(
            name: "promo",
            dependencies: [.product(name: "Flipbook", package: "Flipbook")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
