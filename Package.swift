// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "token_island",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "token_island", targets: ["token_island"])
    ],
    targets: [
        .executableTarget(
            name: "token_island",
            path: "Sources/token_island"
        )
    ]
)
