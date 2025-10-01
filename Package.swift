// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "devenv",
  platforms: [
    .macOS(.v10_15)
  ],
  dependencies: [
    // Official deps
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "4.0.0"),

    // Third-Party
    .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .executableTarget(
      name: "devenv",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "TOMLKit", package: "TOMLKit"),
        .product(name: "Crypto", package: "swift-crypto"),
      ]
    )
  ]
)
