// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "unified_esc_pos_printer",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "unified-esc-pos-printer",
            targets: ["unified_esc_pos_printer"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "unified_esc_pos_printer",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
