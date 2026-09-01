// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Swiftra",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "App", targets: ["App"]),
        .executable(name: "Swiftra", targets: ["Run"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "FluentMySQLDriver", package: "fluent-mysql-driver"),
            ],
            path: ".",
            exclude: ["Run", "Tests", "Resources", "Config", "work", "outputs", "README.md", ".gitignore", "Package.resolved"],
            sources: ["App", "Routes", "Database"]
        ),
        .executableTarget(name: "Run", dependencies: [.target(name: "App")], path: "Run"),
        .testTarget(name: "AppTests", dependencies: [.target(name: "App"), .product(name: "VaporTesting", package: "vapor")], path: "Tests/AppTests"),
    ]
)
