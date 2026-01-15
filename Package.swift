// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "steve",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "steve", targets: ["steve"])
    ],
    targets: [
        .executableTarget(
            name: "steve"
        ),
        .testTarget(
            name: "steveTests",
            dependencies: ["steve"]
        )
    ]
)
