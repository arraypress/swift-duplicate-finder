// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-duplicate-finder",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
    ],
    products: [
        .library(name: "DuplicateFinder", targets: ["DuplicateFinder"]),
    ],
    targets: [
        .target(name: "DuplicateFinder"),
        .testTarget(name: "DuplicateFinderTests", dependencies: ["DuplicateFinder"]),
    ]
)
