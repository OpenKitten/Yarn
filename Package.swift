// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.


import PackageDescription

let package = Package(
    name: "Lynx",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "Lynx",
            targets: ["Lynx"]),
        .executable(
            name: "YarnExample",
            targets: ["LynxExample"]),
    ],
    dependencies: [
        .package(url: "http://github.com/OpenKitten/CryptoKitten.git", .branch("master"))
        // Dependencies declare other packages that this package depends on.
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "Lynx",
            dependencies: ["CryptoKitten"]),
        .target(
            name: "LynxExample",
            dependencies: ["Lynx"]),
        .testTarget(
            name: "Lynxtests",
            dependencies: ["Lynx"]),
    ]
)
