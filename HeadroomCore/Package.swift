// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadroomCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HeadroomCore", targets: ["HeadroomCore"]),
        .library(name: "HeadroomUI", targets: ["HeadroomUI"]),
    ],
    targets: [
        .target(name: "HeadroomCore"),
        .target(name: "HeadroomUI", dependencies: ["HeadroomCore"], resources: [.process("Fonts")]),
        .testTarget(name: "HeadroomUITests", dependencies: ["HeadroomUI", "HeadroomCore"]),
        .testTarget(name: "HeadroomCoreTests", dependencies: ["HeadroomCore"], resources: [.copy("Fixtures")]),
    ]
)
