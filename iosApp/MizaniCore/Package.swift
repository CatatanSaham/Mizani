// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MizaniCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "MizaniCore", targets: ["MizaniCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", exact: "4.20.0"),
    ],
    targets: [
        .target(
            name: "MizaniCore",
            dependencies: [
                .product(name: "SQLCipher", package: "SQLCipher.swift"),
            ],
            cSettings: [
                .define("SQLITE_HAS_CODEC", to: nil),
            ],
            swiftSettings: [
                .define("SQLITE_HAS_CODEC", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "MizaniCoreTests",
            dependencies: ["MizaniCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
