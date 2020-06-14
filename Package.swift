// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "ThumbworksBot",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "ThumbworksBot", targets: ["App"]),
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.0.0-rc.1.2"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        .package(name: "QueuesFluentDriver", url: "https://github.com/m-barthelemy/vapor-queues-fluent-driver.git", from: "0.3.7"),
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "Leaf", package: "leaf"),
            .product(name: "Vapor", package: "vapor"),
            .product(name: "Fluent", package: "fluent"),
            .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            .product(name: "QueuesFluentDriver", package: "QueuesFluentDriver"),
            ]
        ),
        .target(name: "Run", dependencies: [.target(name: "App"),]),
        .testTarget(name: "AppTests",
                    dependencies: [.target(name: "App"),
                                   .product(name: "XCTVapor",
                                            package: "vapor")])
    ]
)

