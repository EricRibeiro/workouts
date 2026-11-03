// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "WorkoutsKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "WorkoutsKit", targets: ["WorkoutsKit"])
    ],
    targets: [
        .target(
            name: "WorkoutsKit",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .testTarget(
            name: "WorkoutsKitTests",
            dependencies: ["WorkoutsKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ]
)
