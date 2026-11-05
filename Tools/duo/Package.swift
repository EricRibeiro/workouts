// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "duo",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "duo", targets: ["duo"]),
        .library(name: "DuoKit", targets: ["DuoKit"]),
    ],
    targets: [
        .target(name: "DuoKit"),
        .executableTarget(name: "duo", dependencies: ["DuoKit"]),
        .testTarget(
            name: "DuoKitTests",
            dependencies: ["DuoKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
